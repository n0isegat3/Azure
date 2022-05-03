#variables
[string]$Prefix = 'kusto'
[string]$Region = 'westeurope'
[string]$ProviderTenantID = '2b1c7905-1691-49c2-b3bd-ad99fb6881c5'
[string]$SubscriptionId = 'a0ea77b1-2cd9-4549-ab55-c003fb12b853'
[string]$WorkbooksFolder = './AzureSentinel/resources/workbooks'
[string]$WatchlistsFolder = './AzureSentinel/resources/watchlists'
[string]$PlaybooksFolder = './AzureSentinel/resources/playbooks'
[string]$HuntingQueryCSVDefinitions = './AzureSentinel/resources/huntingqueries/huntingQueries.csv'
[string]$windowsEventLogsFolder = './AzureSentinel/resources/windowseventlogs'
[string]$HuntingQueryFolder = './AzureSentinel/resources/huntingqueries'

#prep variables
$Random = get-date -f 'yyyyMMddhhmm'
$ResourceGroupName = ('{0}-training-{1}' -f $Prefix, $Random)
$DeploymentName = ('{0}-training-{1}' -f $Prefix, $Random)
$WorkspaceName = ('{0}-training-{1}' -f $Prefix, $Random)


$CustomerHosted = $true #$false for deployment to provider tenant / $true for deployment to customer's tenant

#for existing RGs and resources fill in the following:
<#
$Random = 202109061228
$ResourceGroupName = 'mssp09062021002-AzS-202109061228'
$WorkspaceName = $ResourceGroupName
$DeploymentName = $ResourceGroupName
#>

#login to azure
az login

#show currently using subscription
az account show --output table

#show all subscriptions
az account list --output table

#set active subscription
az account set --subscription $SubscriptionId

#create resource group
az group create --name $ResourceGroupName --location $Region

#create SPN
if ($CustomerHosted -eq $true) {
    az ad sp create-for-rbac --name ('{0}-AzS-{1}' -f $Prefix, $Random)
}

#delegate for Azure Lighthouse
if ($CustomerHosted -eq $true) {
    az deployment create `
        --location $Region `
        --name $DeploymentName `
        --template-file ./AzureSentinel/customer-hosted/lighthouse-contributor.json `
        --parameters ('rgName={0}' -f $ResourceGroupName) `
        --parameters ('managedByTenantId={0}' -f $ProviderTenantID)
}

#region deploy Azure Sentinel and deploy Analytics Rules
$SentinelDeploymentResultJSON = az deployment group create `
    --name $DeploymentName `
    --resource-group $ResourceGroupName `
    --template-file ./AzureSentinel/provider-hosted/azuredeploy.json `
    --parameters ./AzureSentinel/provider-hosted/azuredeploy.parameters.json `
    --parameters ('workspaceName={0}' -f $WorkspaceName)

Connect-AzAccount
Get-AzResourceProvider -ProviderNamespace Microsoft.OperationalInsights

$SentinelDeploymentResult = $SentinelDeploymentResultJSON | ConvertFrom-Json
New-Object -TypeName psobject -Property @{
    workspaceId        = $SentinelDeploymentResult.properties.outputs.workspaceIdOutput.value
    workspaceKey       = $SentinelDeploymentResult.properties.outputs.workspaceKeyOutput.value
    workspaceName      = $SentinelDeploymentResult.properties.outputs.workspaceName.value
    dataConnectorsList = $SentinelDeploymentResult.properties.outputs.dataConnectorsList.value
}
#endregion deploy Azure Sentinel and deploy Analytics Rules

#region deploy Azure Log Analytics Windows Event Logs
$windowsEventLogARMTemplates = Get-ChildItem -Path $windowsEventLogsFolder -Filter *.json

foreach ($windowsEventLogARMTemplate in $windowsEventLogARMTemplates) {
    
    Write-Output ('Deploying Windows Event Log {0}...' -f $windowsEventLogARMTemplate.BaseName.split('-')[-1])
    az deployment group create `
        --name ('{0}-{1}' -f $DeploymentName, $windowsEventLogARMTemplate.BaseName) `
        --resource-group $ResourceGroupName `
        --parameters ('workspaceName={0}' -f $WorkspaceName) `
        --parameters ('resourceDeploymentName="{0}"' -f $windowsEventLogARMTemplate.BaseName) `
        --template-file $windowsEventLogARMTemplate.FullName
}
#endregion deploy Azure Log Analytics Windows Event Logs

#region deploy Azure Sentinel playbooks
$playbookARMTemplates = Get-ChildItem -Path $PlaybooksFolder -Filter *.json

foreach ($playbookARMTemplate in $playbookARMTemplates) {
    Write-Output ('Deploying playbook {0}...' -f $playbookARMTemplate.BaseName)
    az deployment group create `
        --name ('{0}-{1}' -f $DeploymentName, $playbookARMTemplate.BaseName.Replace(' ', '')) `
        --resource-group $ResourceGroupName `
        --template-file $playbookARMTemplate.FullName
    #--parameters ('workbookSourceId={0}' -f "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.operationalinsights/workspaces/$WorkspaceName")
}
#endregion deploy Azure Sentinel playbooks

#region deploy Azure Sentinel workbooks
$workbookARMTemplates = Get-ChildItem -Path $WorkbooksFolder -Filter *.json

foreach ($workbookARMTemplate in $workbookARMTemplates) {
    Write-Output ('Deploying workbook {0}...' -f $workbookARMTemplate.BaseName)
    az deployment group create `
        --name ('{0}-{1}' -f $DeploymentName, $workbookARMTemplate.BaseName.Replace(' ', '')) `
        --resource-group $ResourceGroupName `
        --template-file $workbookARMTemplate.FullName `
        --parameters ('workbookSourceId={0}' -f "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.operationalinsights/workspaces/$WorkspaceName")
}
#endregion deploy Azure Sentinel workbooks

#region deploy Azure Sentinel watchlists
$watchlistARMTemplates = Get-ChildItem -Path $WatchlistsFolder -Filter *.json

foreach ($watchlistARMTemplate in $watchlistARMTemplates) {
    Write-Output ('Deploying watchlist {0}...' -f $watchlistARMTemplate.BaseName)
    az deployment group create `
        --name ('{0}-{1}' -f $DeploymentName, $watchlistARMTemplate.BaseName.Replace(' ', '')) `
        --resource-group $ResourceGroupName `
        --template-file $watchlistARMTemplate.FullName `
        --parameters ('workspaceName={0}' -f $WorkspaceName)
}
#endregion deploy Azure Sentinel watchlists

#region deploy Azure Sentinel hunting rules via ARM
foreach ($HuntingQueryDefinition in (Import-Csv -Path $HuntingQueryCSVDefinitions -Delimiter "|")) {
    Write-Output ('Deploying hunting query {0} with tactics {1}' -f $HuntingQueryDefinition.HuntingQueryName, $HuntingQueryDefinition.HuntingQueryTactics)

    az deployment group create `
        --name ('{0}-{1}' -f $DeploymentName, $HuntingQueryDefinition.HuntingQueryName) `
        --resource-group $ResourceGroupName `
        --template-file ./AzureSentinel/resources/huntingqueries/huntingQuery.json `
        --parameters ('workspaceName={0}' -f $WorkspaceName) `
        --parameters ('huntingQueryName="{0}"' -f $HuntingQueryDefinition.HuntingQueryName) `
        --parameters ('huntingQueryDisplayName="{0}"' -f $HuntingQueryDefinition.HuntingQueryDisplayName) `
        --parameters ('huntingQuery="{0}"' -f ([system.io.file]::ReadAllText((Join-Path $HuntingQueryFolder ('{0}.kql' -f $HuntingQueryDefinition.HuntingQueryName))))) `
        --parameters ('huntingQueryTactics={0}' -f $HuntingQueryDefinition.HuntingQueryTactics) `
        --parameters ('huntingQueryDescription={0}' -f $HuntingQueryDefinition.HuntingQueryDescription)
}
#endregion deploy Azure Sentinel hunting rules via ARM

$SentinelDeploymentResult = New-Object -type psobject -Property @{

WorkspaceId = 'e3a1cece-2c5d-4e47-bec1-29787b00fea9'
WorkspaceKey = 'SwfGfzqjQdZyY6jN676kmgTf0iTIEbtXz1hzUNbA8ccAAV73vHCf4GXwv1lakxPEaCkze2w8Jvly+yZYXNhnXA=='
}

#region sample data from Sentinel github
Install-Script Upload-AzMonitorLog
new-item -itemtype directory -path C:\ -name Temp -errorAction SilentlyContinue
cd C:\Temp
git clone https://github.com/Azure/Azure-Sentinel.git
cd 'Azure-Sentinel\Sample Data'
gci -recurse -include *.csv,*.json | select-object -Property basename,fullname | foreach-object {
    if ($_.fullname -like "*.csv") {
        Write-Host ('Uploading file {0}' -f $_.fullname)
        Import-CSV $_.fullname | Upload-AzMonitorLog.ps1 `
        -WorkspaceId $SentinelDeploymentResult.WorkspaceId `
        -WorkspaceKey $SentinelDeploymentResult.WorkspaceKey `
            -LogTypeName $_.basename.replace(' ','').replace('-','_').replace('.','_')
    }
    if ($_.fullname -like "*.json") {
        Write-Host ('Uploading file {0}' -f $_.fullname)
        Get-Content $_.fullname | ConvertFrom-JSON | Upload-AzMonitorLog.ps1 `
        -WorkspaceId $SentinelDeploymentResult.WorkspaceId `
        -WorkspaceKey $SentinelDeploymentResult.WorkspaceKey `
            -LogTypeName $_.basename.replace(' ','').replace('-','_').replace('.','_')
    }
}

#endregion sample data from Sentinel github

#region sample CR data
Install-Script Upload-AzMonitorLog
new-item -itemtype directory -path C:\ -name Temp2 -errorAction SilentlyContinue
cd C:\Temp2
git clone https://github.com/n0isegate/security-datasets #under development
gci -recurse -include *.csv,*.json | select-object -Property basename,fullname | foreach-object {
    if ($_.fullname -like "*.csv") {
        Write-Host ('Uploading file {0}' -f $_.fullname)
        Import-CSV $_.fullname | Upload-AzMonitorLog.ps1 `
        -WorkspaceId $SentinelDeploymentResult.WorkspaceId `
        -WorkspaceKey $SentinelDeploymentResult.WorkspaceKey `
            -LogTypeName $_.basename.replace(' ','').replace('-','_').replace('.','_')
    }
    if ($_.fullname -like "*.json") {
        Write-Host ('Uploading file {0}' -f $_.fullname)
        Get-Content $_.fullname | ConvertFrom-JSON | Upload-AzMonitorLog.ps1 `
        -WorkspaceId $SentinelDeploymentResult.WorkspaceId `
        -WorkspaceKey $SentinelDeploymentResult.WorkspaceKey `
            -LogTypeName $_.basename.replace(' ','').replace('-','_').replace('.','_')
    }
}
#endregion sample CR data
#delete resource group
<#
az group delete --name $ResourceGroupName
#>


function Send-ObjectToAzLa {

    <# 
    .DESCRIPTION 
      Script to upload PowerShell objects to Azure Monitor Logs using the Data Collector API.  
 
    .PARAMETER WorkspaceId 
        The Workspace ID of the workspace that would be used to store this data
 
    .PARAMETER WorkspaceKey 
        The primary or secondary key of the workspace that would be used to store this data. It can be obtained from the Windows Server tab in the workspace Advanced Settings
     
    .PARAMETER LogTypeName 
        The name of the custom log table that would store these logs. This name will be automatically concatenated with "_CL"
 
    .PARAMETER AddComputerName 
        If this switch is indicated, the script will add to every log record a field called Computer with the current computer name
 
    .PARAMETER TaggedAzureResourceId 
        If exist, the script will associated all uploaded log records with the specified Azure resource. This will enable these log records for resource-centext queries

    .PARAMETER AdditionalDataTaggingName 
        If exist, the script will add to every log record an additional field with this name and with the value that appears in AdditionalDataTaggingValue. This happens only if AdditionalDataTaggingValue is not empty
 
    .PARAMETER AdditionalDataTaggingValue 
        If exist, the script will add to every log record an additional field with this value. The field name would be as specified in AdditionalDataTaggingName. If AdditionalDataTaggingName is empty, the field name will be "DataTagging"
 
    .EXAMPLE 
      Import-Csv .\testcsv.csv | .\Upload-AzMonitorLog.ps1 -WorkspaceId '69f7ec3e-cae3-458d-b4ea-6975385-6e426' -WorkspaceKey $WSKey -LogTypeName 'MyNewCSV' -AddComputerName -AdditionalDataTaggingName "MyAdditionalField" -AdditionalDataTaggingValue "Foo"
      Will upload the CSV file as a custom log to Azure Monitor Logs (AKA:Log Analytics)
   
    .EXAMPLE 
      Import-Csv .\testcsv.csv | .\Upload-AzMonitorLog.ps1 -WorkspaceId '69f7ec3e-cae3-458d-b4ea-6975385-6e426' -WorkspaceKey $WSKey -LogTypeName 'MyNewCSV' -AddComputerName -AdditionalDataTaggingName "MyAdditionalField" -AdditionalDataTaggingValue "Foo"
      Will upload the CSV file as a custom log to Azure Monitor Logs (AKA:Log Analytics)
 
    .LINK 
        This script posted to and discussed at the following locations:PowerShell Gallery      
        https://www.powershellgallery.com/packages/Upload-AzMonitorLog
    #>
    param (
        [Parameter(mandatory=$true,ValueFromPipeline=$true)]$input,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$WorkspaceId,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$WorkspaceKey,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$LogTypeName,
        [Parameter(Mandatory=$false)][switch]$AddComputerName,
        [Parameter(Mandatory=$false)][string]$TaggedAzureResourceId,    
        [Parameter(Mandatory=$false)][string]$AdditionalDataTaggingName,    
        [Parameter(Mandatory=$false)][string]$AdditionalDataTaggingValue,
        [Parameter(Mandatory=$false)][string]$TimestampPropertyToUseFromInput = ''
        )

    Write-Output ("Start process " + $input.Length.ToString("N0") + " items and uploading them to Azure Log Analytcs")

    $InputTypeName = $input.GetType().Name
    switch -Exact ($InputTypeName)
    {
        "ArrayListEnumeratorSimple" { $data = $input | ConvertTo-Json -Compress; Break }
        default { $data = $input.GetType().Name }
    }

    $customerId = $WorkspaceId
    $sharedKey = $WorkspaceKey

    # Specify the name of the record type that you'll be creating
    $LogType = $LogTypeName

    # Specify a field with the created time for the records
    $TimeStampField = "DateValue" #OBSOLETE exist just for backward compatability

    if ($TimestampPropertyToUseFromInput.Length -gt 0){
        $TimeStampField = $TimestampPropertyToUseFromInput
    }
    else {
        $TimeStampField = Get-Date ([datetime]::UtcNow) -Format O
    }

    # Add computer name for each record if needed
    if ($AddComputerName)
    {
        $compName = $env:COMPUTERNAME
        if ($ENV:USERDNSDOMAIN -ne $env:COMPUTERNAME) { $compName = $env:COMPUTERNAME + "." + $ENV:USERDNSDOMAIN } #for domain joined computer, add FQDN
        foreach ($row in $input) {$row | Add-Member -MemberType NoteProperty -Name Computer -Value $compName}
    }

    # Add additional tagging if additional tagging is provided
    if ($AdditionalDataTaggingValue)
    {
        if(!($AdditionalDataTaggingName)) { $AdditionalDataTaggingName = "DataTagging" }
        foreach ($row in $input) {$row | Add-Member -MemberType NoteProperty -Name $AdditionalDataTaggingName -Value $AdditionalDataTaggingValue}
    }

    # Create json object based on the PowerShell data
    try
    {   
        $json = $input | ConvertTo-Json -Compress
    }
    catch
    {
        throw("Input data cannot be converted into a JSON object. Please make sure that the input data is a standard PowerShell table")
    }


    # Create the function to create the authorization signature
    Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
    {
        $xHeaders = "x-ms-date:" + $date
        $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes = [Convert]::FromBase64String($sharedKey)

        $sha256 = New-Object System.Security.Cryptography.HMACSHA256
        $sha256.Key = $keyBytes
        $calculatedHash = $sha256.ComputeHash($bytesToHash)
        $encodedHash = [Convert]::ToBase64String($calculatedHash)
        $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
        return $authorization
    }


    #Format the post request
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $body = ([System.Text.Encoding]::UTF8.GetBytes($json))
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "x-ms-AzureResourceId" = $TaggedAzureResourceId
        "time-generated-field" = $TimeStampField;
    }

    #validate that payload data does not exceed limits
    if ($body.Length -gt (31.9 *1024*1024))
    {
        throw("Upload payload is too big and exceed the 32Mb limit for a single upload. Please reduce the payload size. Current payload size is: " + ($body.Length/1024/1024).ToString("#.#") + "Mb")
    }

    Write-Output ("Upload payload size is " + ($body.Length/1024).ToString("#.#") + "Kb")

    ##### Send the Web request
    try
    {
        $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    }
    catch
    {
        if ($_.Exception.Message.startswith('The remote name could not be resolved'))
        {
            throw ("Error - data could not be uploaded. Might be because workspace ID or private key are incorrect")
        }

        throw ("Error - data could not be uploaded: " + $_.Exception.Message)
    }
        
    # Present message according to the response code
    if ($response.StatusCode -eq 200) 
    { Write-Output  "200 - Data was successfully uploaded" }
    else
    { throw ("Server returned an error response code:" + $response.StatusCode)}

}