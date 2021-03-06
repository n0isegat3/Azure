[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [Parameter(Mandatory=$true)][string]$Workspace,
    [Parameter(Mandatory=$true)][string[]]$Connectors
)

#limit analytics rules types if needed. supported values are listed in the next comment. these are not covering all available analytics rules types in Sentinel but only
#those which are supported for automated deployment via API as documented in API documentation
## "Fusion","Scheduled","MicrosoftSecurityIncidentCreation","NRT","MLBehaviorAnalytics","ThreatIntelligence"
## following types are currently not supported by API in specific regions and deployment can produce errors: "Anomaly"
## IMPORTANT NOTE> "Fusion" can be deployed only with $deployChoice = 'all' as Fusion rule has no required Data Connectors in template!
[string[]]$analyticsRulesKindsToDeploy = "Scheduled","MicrosoftSecurityIncidentCreation","NRT","MLBehaviorAnalytics","ThreatIntelligence"

#limit analytics rules to deploy if they are in Preview - contains string '(Preview)' in name:
[bool]$deployAnalyticsRulesInPreview = $true

#API version (https://github.com/Azure/azure-rest-api-specs/tree/main/specification/securityinsights/resource-manager/Microsoft.SecurityInsights):
[string]$sentinelAPIVersion = '2022-05-01-preview'
#[string]$sentinelAPIVersion = '2021-10-01-preview'
#[string]$sentinelAPIVersion = '2019-01-01-preview'

$context = Get-AzContext

if(!$context){
    Connect-AzAccount
    $context = Get-AzContext
}

$SubscriptionId = $context.Subscription.Id

Write-Host "Connected to Azure with subscription: $($context.Subscription)" -ForegroundColor magenta

$baseUri = "/subscriptions/${SubscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.OperationalInsights/workspaces/${Workspace}"
$templatesUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRuleTemplates?api-version=$sentinelAPIVersion"
$alertUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRules/"
$alreadyDeployedAlertsUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRules?api-version=$sentinelAPIVersion"

Write-Host ('Loading all available Analytics Rules...') -ForegroundColor magenta
try {
    $alertRulesTemplates = ((Invoke-AzRestMethod -Path $templatesUri -Method GET).Content | ConvertFrom-Json).value
}
catch {
    Write-Error "Unable to get Analytics rules with error code: $($_.Exception.Message)" -ErrorAction Stop
}

Write-Host ('Loading all already deployed Analytics Rules...') -ForegroundColor magenta
try {
    $alreadyDeployedAlertRules = ((Invoke-AzRestMethod -Path $alreadyDeployedAlertsUri -Method GET).Content | ConvertFrom-Json).value
}
catch {
    Write-Error "Unable to get all already deployed Analytics rules with error code: $($_.Exception.Message)" -ErrorAction Stop
}

$enabledAnalyticsRules = @() #only for logging

if ($Connectors){
    foreach ($item in $alertRulesTemplates) {
        if ($item.properties.displayName -in $alreadyDeployedAlertRules.properties.displayName) {
            Write-Host ('Analytics rule with name {0} already deployed. Will be skipped.' -f $item.properties.displayName) -ForegroundColor yellow
            continue
        }
        if ($deployAnalyticsRulesInPreview -eq $false -and $item.properties.displayName -like "*(Preview)*") {
            continue
        }

        foreach ($connector in $item.properties.requiredDataConnectors) {
            if ($connector.connectorId -in $Connectors) {
                if ($item.kind -in $analyticsRulesKindsToDeploy) {
                    $guid = New-Guid
                    $alertUriGuid = $alertUri + $guid + ('?api-version={0}' -f $sentinelAPIVersion)

                    switch ($item.kind) {
                        'Scheduled' {
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
                                techniques = $item.properties.techniques
                                triggerOperator = $item.properties.triggerOperator
                                triggerThreshold = $item.properties.triggerThreshold
                            }
                        }
                        'NRT' {
                            $properties = @{
                                displayName = $item.properties.displayName
                                enabled = $true
                                suppressionDuration = "PT5H"
                                suppressionEnabled = $false
                                alertRuleTemplateName = $item.name
                                description = $item.properties.description
                                query = $item.properties.query
                                severity = $item.properties.severity
                                tactics = $item.properties.tactics
                                techniques = $item.properties.techniques
                            }
                        }
                        'MicrosoftSecurityIncidentCreation' {
                            $properties = @{
                                displayName = $item.properties.displayName
                                enabled = $true
                                productFilter = $item.properties.productFilter
                                alertRuleTemplateName = $item.name
                                description = $item.properties.description
                                displayNamesExcludeFilter = ''
                                displayNamesFilter = ''
                                severitiesFilter = ''
                            }
                        }
                        "Anomaly" {
                            $properties = @{
                                displayName = $item.properties.displayName
                                isDefaultRule = $true
                                enabled = $true
                                ruleStatus = "Production" #The status (Flighting/Production) of the Anomaly analytics rule that generated this anomaly.
                                alertRuleTemplateName = $item.name
                                tactics = $item.properties.tactics
                                techniques = $item.properties.techniques
                                anomalyVersion = $item.properties.anomalyDefinitionVersion
                                frequency = $item.properties.frequency
                            }
                        }
                        "MLBehaviorAnalytics" {
                            $properties = @{
                                enabled = $true
                                alertRuleTemplateName = $item.name
                            }
                        }
                        default {
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
                                techniques = $item.properties.techniques
                                triggerOperator = $item.properties.triggerOperator
                                triggerThreshold = $item.properties.triggerThreshold
                            }
                        }
                    }

                    $alertBody = @{}
                    $alertBody | Add-Member -NotePropertyName kind -NotePropertyValue $item.kind -Force
                    $alertBody | Add-Member -NotePropertyName properties -NotePropertyValue $properties
                    
                    Write-Host ('Deploying Analytics Rule {0}...' -f $alertBody.properties.displayName) -ForegroundColor magenta

                    try{
                        $responseREST = Invoke-AzRestMethod -Path $alertUriGuid -Method PUT -Payload ($alertBody | ConvertTo-Json -Depth 3)
                    }
                    catch {
                        Write-Verbose $_
                        Write-Error "Unable to create alert rule with error code: $($_.Exception.Message)" -ErrorAction Stop
                    }

                    if ($responseREST.Content -like "*error*") {
                        Write-Host ('Error deploying Analytics rule {0} with error message: {1}' -f $item.properties.displayName,($responseREST.Content | ConvertFrom-Json).Error.Message) -ForegroundColor Red
                    }

                    #region Only for logging
                    $info = @{
                        displayName = $item.properties.displayName
                        description = $item.properties.description
                        requiredDataConnector = $connector.connectorId
                        kind = $item.kind
                        RESTResponseContent = $responseREST.Content
                        RESTResponseStatusCode = $responseREST.StatusCode
                    }

                    $enabledAnalyticsRules += (New-Object -TypeName psobject -Property $info)
                    #endregion

                    break
                }
            }
        }
    }
}

Write-Host ('Done. Processed {0} Analytics rules. Error deploying {1} Analytics rules.' -f $enabledAnalyticsRules.count,($enabledAnalyticsRules | Where-Object {$_.RESTResponseContent -like "*error*"}).count) -ForegroundColor magenta
$enabledAnalyticsRules | Where-Object {$_.RESTResponseContent -like "*error*"}