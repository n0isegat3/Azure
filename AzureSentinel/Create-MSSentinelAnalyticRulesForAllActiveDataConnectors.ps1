<#
    .SYNOPSIS
    Creates Microsoft Sentinel Analytic Rules from Analytic Rules templates for all active Microsoft Sentinel Data Connectors

    .DESCRIPTION
    Creates Microsoft Sentinel Analytic Rules from Analytic Rules templates for all active Microsoft Sentinel Data Connectors

    .PARAMETER ResourceGroup
    Specifies the name of Azure Resource Group containing the Microsoft Sentinel log analytics workspace.

    .PARAMETER Workspace
    Specifies the name of Microsoft Sentinel log analytics workspace.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Returns a HTTP responses for REST calls.

    .EXAMPLE
    PS> .\Create-MSSentinelAnalyticRulesForAllActiveDataConnectors.ps1 -ResourceGroup 'resgroup-123' -Workspace 'sentinelwks-123'
        
    Creates Microsoft Sentinel analytic rules for all active data connectors in resource group resgroup-123 and workspace sentinelwks-123

    .NOTES
    Author: Jan Marek, Cyber Rangers, www.cyber-rangers.com
#>

param(
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [Parameter(Mandatory=$true)][string]$Workspace
)

$context = Get-AzContext

if(!$context){
    Connect-AzAccount
    $context = Get-AzContext
}


#dev
<#
$ResourceGroup = 'prod_sentinel'
$Workspace = 'cyber-rangers-prod-sentinel'
#>

$SubscriptionId = $context.Subscription.Id

Write-Host "Connected to Azure with subscription: " + $context.Subscription

$baseUri = "/subscriptions/${SubscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.OperationalInsights/workspaces/${Workspace}"
$templatesUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRuleTemplates?api-version=2019-01-01-preview"
$alertUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRules/"
$dataConnectorsUri = "$baseUri/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2020-01-01"


try {
    Write-Verbose "Loading all Analytic rules templates..."
    $alertRulesTemplates = ((Invoke-AzRestMethod -Path $templatesUri -Method GET).Content | ConvertFrom-Json).value
}
catch {
    Write-Verbose $_
    Write-Error "Unable to get Analytic rules with error code: $($_.Exception.Message)" -ErrorAction Stop
}
Write-Verbose ('{0} Analytic rules templates loaded.' -f $alertRulesTemplates.Count)


try {
    Write-Verbose "Loading active Data Connectors..."
    $Connectors = ((Invoke-AzRestMethod -Path $dataConnectorsUri -Method GET).Content | ConvertFrom-Json).value.kind
}
catch {
    Write-Verbose $_
    Write-Error "Unable to get Data Connectors with error code: $($_.Exception.Message)" -ErrorAction Stop
}
Write-Verbose ('{0} active Data Connectors loaded.' -f $Connectors.Count)

#$return = @()

if ($Connectors){
    foreach ($item in $alertRulesTemplates) {
        if ($item.kind -eq "Scheduled"){
            foreach ($connector in $item.properties.requiredDataConnectors) {
                if ($connector.connectorId -in $Connectors){
                    #$return += $item.properties
                    Write-Verbose "Creating Analytic Rule $($item.properties.displayName) for Data Connector $($connector.connectorId)"
                    $guid = New-Guid
                    $alertUriGuid = $alertUri + $guid + '?api-version=2020-01-01'

                    $properties = @{
                        displayName = $item.properties.displayName
                        enabled = $true
                        suppressionDuration = "PT5H"
                        suppressionEnabled = $false
                        alertRuleTemplateName = $item.name
                        description = $item.properties.description
                        query = $item.properties.query
                        queryFrequency = $item.properties.queryFrequency
                        queryPeriod = $item.properties.queryPeriod
                        severity = $item.properties.severity
                        tactics = $item.properties.tactics
                        triggerOperator = $item.properties.triggerOperator
                        triggerThreshold = $item.properties.triggerThreshold
                    }

                    $alertBody = @{}
                    $alertBody | Add-Member -NotePropertyName kind -NotePropertyValue $item.kind -Force
                    $alertBody | Add-Member -NotePropertyName properties -NotePropertyValue $properties

                    try{
                        Invoke-AzRestMethod -Path $alertUriGuid -Method PUT -Payload ($alertBody | ConvertTo-Json -Depth 3)
                    }
                    catch {
                        Write-Verbose $_
                        Write-Error "Unable to create Analytic rule with error code: $($_.Exception.Message)" -ErrorAction Stop
                    }

                    break
                }
            }
        }
    }
} else {
    Write-Warning 'Unable to detect any active Data Connector.'
}

#return $return