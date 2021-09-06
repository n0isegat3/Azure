$bicepFolder = New-Item -ItemType Directory -Path ('{0}\.bicep' -f $env:USERPROFILE) -Force
$bicepFolder.Attributes += 'Hidden'

Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe' -OutFile (Join-Path -Path $bicepFolder.FullName -ChildPath 'bicep.exe')

$Path = (Get-Item -path "HKCU:\Environment" ).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
if (-not $Path.Contains('%USERPROFILE%\.bicep')) { setx PATH ($Path + ';%USERPROFILE%\.bicep') }
if (-not $env:path.Contains($bicepFolder.FullName)) { $env:path += (';{0}' -f $bicepFolder.FullName) }
