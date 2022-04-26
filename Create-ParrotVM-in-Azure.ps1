[string]$SubscriptionId = 'd5eccfc3-103a-487c-93ff-680e10fa7f88'
$sourceDiskName = 'Parrot-Gen2'
$sourceRG = 'RG_VHDTemplates'
$newVMName = 'azn0iseparrot1'
$targetDiskName = $newVMName
$targetRG = 'RG_{0}' -f $targetDiskName
$targetLocation = "West Europe"
$targetOS = "Linux" #"Windows"
$localSourceVHDPath = 'X:\Parrot-Gen2.vhd'

<# prepare parrot for azure
#install parrot 4.12 to hyper-v gen2 vm
#update, upgrade and configure as needed
#configure to allow RDP
#convert dynamic vhdx to fixed vhdx, resize inside the vm, shrink vhdx and convert to fixed vhd - size must be in 1MB increments!
sudo apt update
sudo apt install waagent
reboot
sudo systemctl enable ssh.service
sudo waagent -force -deprovision
export histsize=0
#logoff and shutdown
#>

choco install azure-cli -y
choco upgrade azure-cli -y

#login to azure
az login

#show currently using subscription
az account show --output table

#show all subscriptions
az account list --output table

#set active subscription
az account set --subscription $SubscriptionId

#create empty managed disk
az group create --name $sourceRG --location $targetLocation
az disk create -n $sourceDiskName -g $sourceRG -l $targetLocation --os-type $targetOS --for-upload --upload-size-bytes (get-item $localSourceVHDPath).Length --sku standard_lrs --hyper-v-generation v2

$templateDiskSASURI = $(az disk grant-access -n $sourceDiskName -g $sourceRG --access-level Write --duration-in-seconds 86400 -o tsv)
$templateDiskSASURI = $templateDiskSASURI.Split("`t")[0]

#upload
C:\Tools\azcopy.exe copy $localSourceVHDPath $templateDiskSASURI --blob-type PageBlob

az disk revoke-access -n $name -g $sourceRG

#copy the disk
az group create --name $targetRG --location $targetLocation

[int64]$sourceDiskSizeBytes = $(az disk show -g $sourceRG -n $sourceDiskName --query '[diskSizeBytes]' -o tsv)

az disk create -g $targetRG -n $targetDiskName -l $targetLocation --os-type $targetOS --for-upload --upload-size-bytes $(($sourceDiskSizeBytes+512)) --sku standard_lrs --hyper-v-generation v2

$targetSASURI = $(az disk grant-access -n $targetDiskName -g $targetRG  --access-level Write --duration-in-seconds 86400 -o tsv)

$sourceSASURI = $(az disk grant-access -n $sourceDiskName -g $sourceRG --duration-in-seconds 86400 --query [accessSas] -o tsv)

C:\Tools\azcopy.exe copy $sourceSASURI $targetSASURI --blob-type PageBlob

C:\Tools\azcopy.exe copy $sourceSASURI "https://md-impexp-x4230cnts5d5.z18.blob.storage.azure.net/b0smvzfs1xtq/abcd?sv=2018-03-28&sr=b&si=ada082cd-1650-4c2b-8e9f-b68952ca3281&sig=JaqwWUQOFBg%2FJmpqRj14CCeWLg2TVVanBXBUIxDDnig%3D" --blob-type PageBlob

az disk revoke-access -n $sourceDiskName -g $sourceRG

az disk revoke-access -n $targetDiskName -g $targetRG

az vm create --resource-group $targetRG `
    --location $targetLocation `
    --name $newVMName `
	--os-type $targetOS `
    --attach-os-disk $targetDiskName `
    --public-ip-sku Standard