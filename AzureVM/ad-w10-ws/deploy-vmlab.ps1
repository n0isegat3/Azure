[string]$Prefix = 'azsentinel-webinar'
[string]$Region = 'westeurope'
[string]$SubscriptionId = 'd5eccfc3-103a-487c-93ff-680e10fa7f88'
[bool]$enableMMA = $true
[string]$WorkspaceId = $SentinelDeploymentResultObject.workspaceId
[string]$WorkspaceKey = $SentinelDeploymentResultObject.workspaceKey

#prep variables
$Random = get-date -f 'yyyyMMddhhmm'
$ResourceGroupName = ('{0}-AzS-{1}' -f $Prefix, $Random)
$DeploymentName = ('{0}-AzS-{1}' -f $Prefix, $Random)

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



if ($enableMMA -eq $true) {
    #deploy lab virtual machines for Azure Sentinel lab and connect them to Azure Sentinel workspace
    az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file ./AzureVM/ad-w10-ws/azuredeploy.json `
        --parameters ./AzureVM/ad-w10-ws/azuredeploy.parameters.json `
        --parameters ('enableMonitoringAgent=true workspaceId={0} workspaceKey={1}' -f $WorkspaceId, $WorkspaceKey) `
        --name $DeploymentName
}
else {
    #deploy lab virtual machines for Azure Sentinel lab without connecting to Azure Sentinel workspace
    az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file ./AzureSentinel/templates/ad-w10-ws/azuredeploy.json `
        --parameters ./AzureSentinel/templates/ad-w10-ws/azuredeploy.parameters.json `
        --name $DeploymentName
}
#delete resource group
<#
az group delete --name $ResourceGroupName
#>