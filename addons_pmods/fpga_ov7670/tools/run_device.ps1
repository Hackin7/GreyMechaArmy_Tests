param(
    [string]$Port = 'COM3',
    [Parameter(Mandatory=$true)][string]$File,
    [string]$LogPath,
    [int]$TimeoutSeconds = 60,
    [switch]$SoftReset,
    [switch]$LiveOutput
)
$ErrorActionPreference = 'Stop'
$cameraSerial = [System.IO.Ports.SerialPort]::new($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$cameraSerial.DtrEnable = $true
$cameraSerial.WriteTimeout = 5000
$script:cameraReceiveBuffer = ''
$cameraOutput=''
$cameraError=''
function Read-CameraUntil([string]$Marker, [int]$Seconds, [switch]$Echo) {
    $cameraDeadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $cameraDeadline) {
        $cameraChunk=$cameraSerial.ReadExisting()
        $script:cameraReceiveBuffer += $cameraChunk
        if($Echo -and $cameraChunk) {
            Write-Host -NoNewline ($cameraChunk.Replace([string][char]4,''))
        }
        $cameraEnd = $script:cameraReceiveBuffer.IndexOf($Marker,[StringComparison]::Ordinal)
        if ($cameraEnd -ge 0) {
            $cameraReply = $script:cameraReceiveBuffer.Substring(0,$cameraEnd)
            $script:cameraReceiveBuffer = $script:cameraReceiveBuffer.Substring($cameraEnd+$Marker.Length)
            return $cameraReply
        }
        Start-Sleep -Milliseconds 10
    }
    throw "Console timeout waiting for marker; received: $script:cameraReceiveBuffer"
}
try {
    $cameraSerial.Open()
    $cameraSerial.Write([byte[]](13,3,3),0,3)
    Start-Sleep -Milliseconds 400
    $cameraSerial.Write([byte[]](2,13,3),0,3)
    Start-Sleep -Milliseconds 400
    $null = $cameraSerial.ReadExisting()
    $cameraSerial.Write([byte[]](1),0,1)
    $null = Read-CameraUntil "raw REPL; CTRL-B to exit`r`n>" 5
    if ($SoftReset) {
        # Raw-mode soft reset clears RP2350 peripheral owners without running
        # code.py's normal menu or changing its contents/NVM.
        $cameraSerial.Write([byte[]](4),0,1)
        $null = Read-CameraUntil "raw REPL; CTRL-B to exit`r`n>" 10
    }
    $cameraProgram = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).Path).Replace("`r`n","`n")
    $cameraBytes = [Text.Encoding]::UTF8.GetBytes($cameraProgram)
    for ($cameraPosition=0; $cameraPosition -lt $cameraBytes.Length; $cameraPosition+=128) {
        $cameraLength=[Math]::Min(128,$cameraBytes.Length-$cameraPosition)
        $cameraSerial.Write($cameraBytes,$cameraPosition,$cameraLength)
        Start-Sleep -Milliseconds 10
    }
    $cameraSerial.Write([byte[]](4),0,1)
    $null = Read-CameraUntil 'OK' 5
    $cameraOutput = Read-CameraUntil ([string][char]4) $TimeoutSeconds -Echo:$LiveOutput
    $cameraError = Read-CameraUntil ([string][char]4) 5
    $null = Read-CameraUntil '>' 5
    if ($LogPath) { [IO.File]::WriteAllText($LogPath,$cameraOutput+"`n"+$cameraError) }
    if(-not $LiveOutput) { Write-Output $cameraOutput }
    if ($cameraError) { throw $cameraError }
} catch {
    if($LogPath) {
        [IO.File]::WriteAllText($LogPath,$cameraOutput+$cameraError+$script:cameraReceiveBuffer+"`nRUN_ERROR: "+$_)
    }
    throw
} finally {
    if ($cameraSerial.IsOpen) {
        try { $cameraSerial.Write([byte[]](2),0,1) } catch { }
        $cameraSerial.Close()
    }
    $cameraSerial.Dispose()
}
