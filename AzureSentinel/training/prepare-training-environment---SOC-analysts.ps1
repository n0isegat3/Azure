#variables
[string]$trainingResourceGroup = 'rg-sentinel-training-test'
[string]$vmPrefixes = 'labVM-' #not used so far
[string]$Region = 'westeurope'
[string]$SubscriptionId = 'd5eccfc3-103a-487c-93ff-680e10fa7f88'
[string]$UPNDomain = 'janmareklab.cz'
[string]$studentPassword = 'P@ssw0rd'
[string]$trainerPassword = 'P@ssw0rd'
[string]$vmPassword = 'P@ssw0rd'

#login to azure
az login --use-device-code

#show currently using subscription
az account show --output table

#show all subscriptions
az account list --output table

#set active subscription
az account set --subscription $SubscriptionId



<# cleanup
#delete resource group
Write-Host ('Deleting resource group {0}' -f $trainingResourceGroup)
az group delete --name $trainingResourceGroup --yes --no-wait
#>

#create resource group
az group create --name $trainingResourceGroup --location $Region


#create users
1..15 | foreach-object {
    az ad user create --display-name ('student{0}' -f $_) --password $studentPassword --user-principal-name ('student{0}@{1}' -f $_, $UPNDomain)
}

az ad user create --display-name ('trainer') --password $trainerPassword --user-principal-name ('trainer@{0}' -f $UPNDomain)
az ad user create --display-name ('test') --password $trainerPassword --user-principal-name ('test@{0}' -f $UPNDomain)


#reset passwords for users
1..15 | foreach-object {
    az ad user update --id (az ad user list --upn ('student{0}@{1}' -f $_, $UPNDomain) | ConvertFrom-Json).id --password $studentPassword --force-change-password-next-sign-in false
}
az ad user update --id (az ad user list --upn ('trainer@{0}' -f $UPNDomain) | ConvertFrom-Json).id --password $trainerPassword --force-change-password-next-sign-in false
az ad user update --id (az ad user list --upn ('test@{0}' -f $UPNDomain) | ConvertFrom-Json).id --password $trainerPassword --force-change-password-next-sign-in false

#list users
#az ad user show --id "{principalName}" --query "id" --output tsv
#list roles
#az role definition list --query "[].{name:name, roleType:roleType, roleName:roleName}" --output tsv
1..15 | foreach-object {
    #add role assignments on subscription level
    az role assignment create --assignee ('student{0}@{1}' -f $_, $UPNDomain) `
        --role "Reader" `
        --subscription $SubscriptionId
    #add role assignments on resource group level
    az role assignment create --assignee ('student{0}@{1}' -f $_, $UPNDomain) `
        --role "Owner" `
        --resource-group $trainingResourceGroup
}

'trainer', 'test' | foreach-object {
    #add role assignments on subscription level
    az role assignment create --assignee ('{0}@{1}' -f $_, $UPNDomain) `
        --role "Reader" `
        --subscription $SubscriptionId
    #add role assignments on resource group level
    az role assignment create --assignee ('{0}@{1}' -f $_, $UPNDomain) `
        --role "Owner" `
        --resource-group $trainingResourceGroup
}

Write-Host ('now manually deploy https://github.com/OTRF/Microsoft-Sentinel2Go to resource group {0} and use password {1}' -f $trainingResourceGroup, $vmPassword)

Write-Host ('now manually deploy MMA https://go.microsoft.com/fwlink/?LinkId=828603 and MDA https://aka.ms/dependencyagentwindows on all lab machines')

Write-Host ('now add following xpath to DCR for collecting security events via AMA: "Security!*[System[(EventID=5137)]]" and wait for a few minutes')

Write-Host ('now add new DCR using Azure Monitor to collect Events using the following Xpaths from all machines:')
'Microsoft-Windows-Sysmon/Operational!*'
'Application!*'
'Microsoft-Windows-WMI-Activity/Operational!*'
'System!*'

Write-Host ('now deploy analytics rules using _deploy-sentinel-analytics.ps1')

Write-Host ('now connect to one of Workstations and clear security event log')

Write-Host ('now deploy sysmon parser from https://github.com/BlueTeamLabs/sentinel-attack/blob/master/parser/Sysmon-OSSEM.txt and name it Sysmon')

Write-Host ('now create watchlist VIPUsers with following content:')
@'
User Identifier,User AAD Object Id,User On-Prem Sid,User Principal Name,Tags
,,S-1-5-21-4160168560-1597586489-964206953-1110,jan@mssentinel.local,Red team
,,S-1-5-21-4160168560-1597586489-964206953-1111,daniel@mssentinel.local,Red team
'@

Write-Host ('configure TI TAXII data connector with following config')
@'
"taxiiServer": "https://limo.anomali.com/api/v1/taxii2/feeds",
"collectionId": "107",
"friendlyName": "Anomali-PhishTank",
"userName": "guest",
"password": "guest",
"pollingFrequency": "OnceADay",
'@

Write-Host ('now Invoke Atomic Red Team.')

Write-Host ('Done!')