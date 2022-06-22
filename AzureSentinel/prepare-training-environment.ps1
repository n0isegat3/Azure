#variables
[string]$rgPrefix = 'rg-sentinel-training-'
[string]$vmPrefixes = 'labVM-'
[string]$Region = 'westeurope'
[string]$SubscriptionId = 'd5eccfc3-103a-487c-93ff-680e10fa7f88'
[string]$UPNDomain = 'janmareklab.cz'
[string]$studentPassword = 'P@ssw0rd'
[string]$trainerPassword = 'P@ssw0rd'

#login to azure
az login

#show currently using subscription
az account show --output table

#show all subscriptions
az account list --output table

#set active subscription
az account set --subscription $SubscriptionId

#create resource group
1..15 | foreach-object {
    az group create --name ('{0}student{1}' -f $rgPrefix,$_) --location $Region
}
az group create --name ('{0}trainer' -f $rgPrefix) --location $Region
az group create --name ('{0}test' -f $rgPrefix) --location $Region


#create users
1..15 | foreach-object {
    az ad user create --display-name ('student{0}' -f $_) --password $studentPassword --user-principal-name ('student{0}@{1}' -f $_,$UPNDomain)
}

az ad user create --display-name ('trainer') --password $trainerPassword --user-principal-name ('trainer@{0}' -f $UPNDomain)
az ad user create --display-name ('test') --password $trainerPassword --user-principal-name ('test@{0}' -f $UPNDomain)


#create virtual machine
# Create a virtual network.
10..15 | foreach-object {
    $vmIdentifiedBy = 'student{0}' -f $_
    az network vnet create `
        --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
        --name ('{0}{1}-vnet' -f $vmPrefixes,$vmIdentifiedBy) `
        --address-prefixes 10.0.0.0/16 `
        --subnet-name ('{0}{1}-subnet' -f $vmPrefixes,$vmIdentifiedBy) `
        --subnet-prefixes 10.0.1.0/24;

    az network public-ip create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-publicIp-ubuntu' -f $vmPrefixes,$vmIdentifiedBy)

    az network public-ip create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-publicIp-ws19' -f $vmPrefixes,$vmIdentifiedBy)

    az network nsg create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nsg-ubuntu' -f $vmPrefixes,$vmIdentifiedBy)

    az network nsg create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nsg-ws19' -f $vmPrefixes,$vmIdentifiedBy)

    az network nic create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nic-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --vnet-name('{0}{1}-vnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --subnet ('{0}{1}-subnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --network-security-group ('{0}{1}-nsg-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --public-ip-address ('{0}{1}-publicIp-ubuntu' -f $vmPrefixes,$vmIdentifiedBy)

    az network nic create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nic-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --vnet-name('{0}{1}-vnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --subnet ('{0}{1}-subnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --network-security-group ('{0}{1}-nsg-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --public-ip-address ('{0}{1}-publicIp-ws19' -f $vmPrefixes,$vmIdentifiedBy)

    #get urn for VM
    #az vm image list -f Ubuntu --location $Region;
    #az vm image list -f WindowsServer --location $Region; 
    ## az vm image list -f RHEL --location southeastasia;
    ## az vm image list -f Debian --location southeastasia;
    ## az vm image list -f openSUSE --location southeastasia;

    az vm create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --nics ('{0}{1}-nic-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --image UbuntuLTS `
    --admin-username ('student') `
    --admin-password $studentPassword;

    az vm create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --nics ('{0}{1}-nic-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --image Win2019Datacenter `
    --admin-username ('student') `
    --admin-password $studentPassword `
    --computer-name $vmIdentifiedBy

    az vm open-port `
    --port 22 `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy);

    az vm open-port `
    --port 3389 `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy);

    #az group delete --name MyResourceGroup;

    start-sleep -seconds 30
    az vm stop --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait
    az vm stop --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait

    az vm deallocate --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait
    az vm deallocate --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait
}

'trainer','test' | foreach-object {
    $vmIdentifiedBy = '{0}' -f $_
    az network vnet create `
        --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
        --name ('{0}{1}-vnet' -f $vmPrefixes,$vmIdentifiedBy) `
        --address-prefixes 10.0.0.0/16 `
        --subnet-name ('{0}{1}-subnet' -f $vmPrefixes,$vmIdentifiedBy) `
        --subnet-prefixes 10.0.1.0/24;

    az network public-ip create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-publicIp-ubuntu' -f $vmPrefixes,$vmIdentifiedBy)

    az network public-ip create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-publicIp-ws19' -f $vmPrefixes,$vmIdentifiedBy)

    az network nsg create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nsg-ubuntu' -f $vmPrefixes,$vmIdentifiedBy)

    az network nsg create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nsg-ws19' -f $vmPrefixes,$vmIdentifiedBy)

    az network nic create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nic-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --vnet-name('{0}{1}-vnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --subnet ('{0}{1}-subnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --network-security-group ('{0}{1}-nsg-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --public-ip-address ('{0}{1}-publicIp-ubuntu' -f $vmPrefixes,$vmIdentifiedBy)

    az network nic create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-nic-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --vnet-name('{0}{1}-vnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --subnet ('{0}{1}-subnet' -f $vmPrefixes,$vmIdentifiedBy) `
    --network-security-group ('{0}{1}-nsg-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --public-ip-address ('{0}{1}-publicIp-ws19' -f $vmPrefixes,$vmIdentifiedBy)

    #get urn for VM
    #az vm image list -f Ubuntu --location $Region;
    #az vm image list -f WindowsServer --location $Region; 
    ## az vm image list -f RHEL --location southeastasia;
    ## az vm image list -f Debian --location southeastasia;
    ## az vm image list -f openSUSE --location southeastasia;

    az vm create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --nics ('{0}{1}-nic-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) `
    --image UbuntuLTS `
    --admin-username ('student') `
    --admin-password $studentPassword;

    az vm create `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --nics ('{0}{1}-nic-ws19' -f $vmPrefixes,$vmIdentifiedBy) `
    --image Win2019Datacenter `
    --admin-username ('student') `
    --admin-password $studentPassword `
    --computer-name $vmIdentifiedBy

    az vm open-port `
    --port 22 `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy);

    az vm open-port `
    --port 3389 `
    --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) `
    --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy);

    #az group delete --name MyResourceGroup;

    start-sleep -seconds 30
    az vm stop --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait
    az vm stop --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait

    az vm deallocate --name ('{0}{1}-ubuntu' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait
    az vm deallocate --name ('{0}{1}-ws19' -f $vmPrefixes,$vmIdentifiedBy) --resource-group ('{0}{1}' -f $rgPrefix,$vmIdentifiedBy) --no-wait
}