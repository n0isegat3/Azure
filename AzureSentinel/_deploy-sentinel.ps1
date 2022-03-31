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
$ResourceGroupName = ('{0}-SENT-{1}' -f $Prefix, $Random)
$DeploymentName = ('{0}-SENT-{1}' -f $Prefix, $Random)
$WorkspaceName = ('{0}-SENT-{1}' -f $Prefix, $Random)


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

#delete resource group
<#
az group delete --name $ResourceGroupName
#>