param(
    [string]$Port='COM3',
    [ValidateSet(60,600)][int]$DurationSeconds=60,
    [string]$LogPath
)
$ErrorActionPreference='Stop'
$cameraRoot=Split-Path -Parent $PSScriptRoot
$cameraBuild=Join-Path $cameraRoot 'build'
New-Item -ItemType Directory -Path $cameraBuild -Force | Out-Null
if(-not $LogPath) {
    $LogPath=Join-Path $cameraBuild ('measure-'+$DurationSeconds+'s-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
}
$cameraScript=Join-Path $cameraBuild ('measure-'+$DurationSeconds+'s.py')
$cameraSource='duration_seconds='+$DurationSeconds+"`n"+[IO.File]::ReadAllText((Join-Path $cameraRoot 'badge\measure.py'))
[IO.File]::WriteAllText($cameraScript,$cameraSource)
& (Join-Path $PSScriptRoot 'run_device.ps1') -Port $Port -File $cameraScript -LogPath $LogPath -TimeoutSeconds ($DurationSeconds+30) -LiveOutput
Write-Output ('Measurement log: '+$LogPath)
