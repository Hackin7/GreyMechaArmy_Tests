param(
    [string]$Port='COM3',
    [ValidateSet(60,600)][int]$DurationSeconds=60,
    [string]$LogPath,
    [ValidateRange(-1,4)][int]$Mode=-1,
    [switch]$RequireEnabled,
    [ValidateRange(0,600)][int]$WaitForModeSeconds=0
)
$ErrorActionPreference='Stop'
$cameraRoot=Split-Path -Parent $PSScriptRoot
$cameraBuild=Join-Path $cameraRoot 'build'
New-Item -ItemType Directory -Path $cameraBuild -Force | Out-Null
if(-not $LogPath) {
    $LogPath=Join-Path $cameraBuild ('measure-'+$DurationSeconds+'s-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
}
$cameraScript=Join-Path $cameraBuild ('measure-'+$DurationSeconds+'s.py')
$cameraStatus=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText((Join-Path $cameraRoot 'badge\status.py'))))
$cameraSource="status_source=__import__('binascii').a2b_base64('"+$cameraStatus+"').decode()`n"
if($Mode -ge 0){$cameraSource+='expected_mode='+$Mode+"`n"}
if($RequireEnabled){$cameraSource+="require_enabled=True`n"}
$cameraSource+='wait_for_mode_seconds='+$WaitForModeSeconds+"`n"
$cameraSource+='duration_seconds='+$DurationSeconds+"`n"+[IO.File]::ReadAllText((Join-Path $cameraRoot 'badge\measure.py'))
[IO.File]::WriteAllText($cameraScript,$cameraSource)
& (Join-Path $PSScriptRoot 'run_device.ps1') -Port $Port -File $cameraScript -LogPath $LogPath -TimeoutSeconds ($DurationSeconds+$WaitForModeSeconds+30) -LiveOutput
Write-Output ('Measurement log: '+$LogPath)
