[cmdletbinding()]
param(
    [Parameter(Mandatory)][string]$OMSWorkspaceID  = '',
    [Parameter(Mandatory)][string]$OMSPrimaryKey = '',
    [string]$SetupFilesPath = $PSScriptRoot
)

Write-Output "Checking operating system architecture..."
switch ((Get-WMIObject Win32_Processor).AddressWidth) {
	'32' {$SetupFile = Join-Path $SetupFilesPath 'MMASetup-i386.exe'}
	'64' {$SetupFile = Join-Path $SetupFilesPath 'MMASetup-AMD64.exe'}
	default {throw 'Unable to detect Operating System architecture.'}
}

Write-Output "Checking setup files..."
if (-not (Test-Path $SetupFile)) {
	throw ('Unable to find required setup file {0}' -f $SetupFile)
}

Write-Output "Installing Microsoft Monitoring Agent..."
$arguments = "/Q:A /R:N /C:`"setup.exe /qn ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_ID=$($OMSWorkspaceID) OPINSIGHTS_WORKSPACE_KEY=$($OMSPrimaryKey) AcceptEndUserLicenseAgreement=1`""
$processresult = Start-Process -FilePath $SetupFile -ArgumentList $arguments -Wait -PassThru
$mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
$mma.AddCloudWorkspace($OMSWorkspaceID, $OMSPrimaryKey)
$mma.ReloadConfiguration()
Write-Output "Microsoft Monitoring Agent completed with exit code $($processresult.ExitCode)"