#provide:
[string]$ResourceGroup = 'rg_prod_sentinel'
[string]$Workspace = 'sentinel-workspace'
[string]$SubscriptionId = 'xxxxx-aaaa-eeee-fxxx-xxxxxx'

$context = Get-AzContext
if (!$context) {
    Connect-AzAccount -DeviceCode
    $context = Get-AzContext
}

Set-AzContext -Subscription $SubscriptionId

Write-Host "Connected to Azure with subscription: $($context.Subscription)" -ForegroundColor magenta

$sentinelIncidents = Get-AzSentinelIncident -ResourceGroupName $ResourceGroup -WorkspaceName $Workspace -Max 10000 | where-object {$_.Title -eq 'Excessive NXDOMAIN DNS Queries (ASIM DNS Schema)'}

$sentinelIncidents.count

#Get-AzADUser -objectId 'xxxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx' | select *
$ownerObject = @{"AssignedTo" = "Jan Marek"; "Email" = "jan@cyber-rangers.com"; "ObjectId" = "xxxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx";"UserPrincipalName" = "jan_cyber-rangers.com#EXT#@xxxx.onmicrosoft.com"}

#change owner to Jan Marek
$currentIncident = 1
foreach ($sentinelIncident in $sentinelIncidents) {
    Write-Host ('Processing incident {0} of {1}: Changing owner...' -f $currentIncident,$sentinelIncidents.Count) -ForegroundColor Magenta
    $sentinelIncident | Update-AzSentinelIncident -Owner $ownerObject -Verbose | Out-Null
    $currentIncident++
}

#close incident with False Positive classification
$currentIncident = 1
foreach ($sentinelIncident in $sentinelIncidents) {
    Write-Host ('Processing incident {0} of {1}: Closing incident...' -f $currentIncident,$sentinelIncidents.Count)
    $sentinelIncident | Update-AzSentinelIncident -Classification FalsePositive -Status "Closed" -ClassificationComment "Bug in analytics rule query logic." -verbose | Out-Null
    $currentIncident++
}