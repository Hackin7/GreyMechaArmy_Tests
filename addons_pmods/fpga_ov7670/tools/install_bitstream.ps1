param(
    [Parameter(Mandatory=$true)][string]$Source,
    [string]$ExpectedHash,
    [string]$ResultPath,
    [switch]$Elevated
)
# Optional persistent install when Windows has marked the badge disk read-only.
# Temporarily clear that attribute only on the badge identified by USB serial,
# copy/verify camera-owned files, and restore its original read-only attribute.
$ErrorActionPreference='Stop'
$cameraSource=(Resolve-Path -LiteralPath $Source).Path
$cameraRoot=Split-Path -Parent $PSScriptRoot
if(-not $ExpectedHash){$ExpectedHash=(Get-FileHash -LiteralPath $cameraSource).Hash}
if((Get-FileHash -LiteralPath $cameraSource).Hash -ne $ExpectedHash){throw 'Source hash changed'}
if(-not $ResultPath){$ResultPath=Join-Path $cameraRoot 'build\badge-install-result.json'}
$cameraIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
$cameraPrincipal=[Security.Principal.WindowsPrincipal]::new($cameraIdentity)
if(-not $cameraPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if($Elevated){throw 'Windows administrator token unavailable'}
    $cameraArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),
        '-Source',('"'+$cameraSource+'"'),'-ExpectedHash',$ExpectedHash,
        '-ResultPath',('"'+$ResultPath+'"'),'-Elevated')
    Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $cameraArguments
    Write-Output ('Windows UAC requested. Result file: '+$ResultPath)
    return
}
$cameraDisk=$null
$cameraWasReadonly=$false
$cameraResult=@{success=$false;source_sha256=$ExpectedHash;files=@()}
try {
    $cameraMatches=@(Get-Disk | Where-Object {$_.SerialNumber -and $_.SerialNumber.Trim() -eq '335CFEB138350510'})
    if($cameraMatches.Count -ne 1){throw 'Expected exactly one matching GreyMecha USB disk'}
    $cameraDisk=$cameraMatches[0]
    if($cameraDisk.FriendlyName -ne 'NUS Grey Grey Mecha Army'){throw 'Unexpected USB disk identity'}
    $cameraVolumes=@($cameraDisk | Get-Partition | Get-Volume | Where-Object {$_.FileSystemLabel -eq 'CIRCUITPY' -and $_.DriveLetter})
    if($cameraVolumes.Count -ne 1){throw 'Expected CIRCUITPY volume on the matching badge'}
    $cameraDrive=$cameraVolumes[0].DriveLetter
    $cameraWasReadonly=$cameraDisk.IsReadOnly
    if($cameraWasReadonly){$cameraDisk | Set-Disk -IsReadOnly $false}
    $cameraCopies=@(
        @($cameraSource,'fpga\app_bitstreams\fpga_ov7670.bit'),
        @((Join-Path $cameraRoot 'badge\status.py'),'apps\ov7670\status.py'),
        @((Join-Path $cameraRoot 'badge\measure.py'),'apps\ov7670\measure.py'))
    foreach($cameraPair in $cameraCopies) {
        $cameraTarget=Join-Path ($cameraDrive+':\') $cameraPair[1]
        $cameraTemporary=$cameraTarget+'.upload'
        $cameraPayload=[IO.File]::ReadAllBytes($cameraPair[0])
        $cameraStream=[IO.FileStream]::new($cameraTemporary,[IO.FileMode]::Create,[IO.FileAccess]::Write,
            [IO.FileShare]::Read,65536,[IO.FileOptions]::WriteThrough)
        try {$cameraStream.Write($cameraPayload,0,$cameraPayload.Length);$cameraStream.Flush($true)}
        finally {$cameraStream.Dispose()}
        $cameraFileHash=(Get-FileHash -LiteralPath $cameraPair[0]).Hash
        if((Get-FileHash -LiteralPath $cameraTemporary).Hash -ne $cameraFileHash){throw 'Badge temporary-file checksum mismatch'}
        Move-Item -LiteralPath $cameraTemporary -Destination $cameraTarget -Force
        Write-VolumeCache -DriveLetter $cameraDrive
        if((Get-FileHash -LiteralPath $cameraTarget).Hash -ne $cameraFileHash){throw 'Badge installed-file checksum mismatch'}
        $cameraResult.files+=@{path=$cameraTarget;sha256=$cameraFileHash}
    }
    $cameraResult.success=$true
} catch {
    $cameraResult.error=[string]$_
} finally {
    if($cameraDisk -and $cameraWasReadonly) {
        try {$cameraDisk | Set-Disk -IsReadOnly $true}
        catch {$cameraResult.success=$false;$cameraResult.restore_error=[string]$_}
    }
    [IO.File]::WriteAllText($ResultPath,($cameraResult | ConvertTo-Json -Depth 5))
}
if(-not $cameraResult.success){throw ('Badge installation failed; see '+$ResultPath)}
