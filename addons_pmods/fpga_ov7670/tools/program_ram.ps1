param(
    [Parameter(Mandatory=$true)][string]$Source,
    [string]$Port='COM3',
    [switch]$ProbePanel
)
# Direct RAM programming over ASCII-encoded serial blocks. No filesystem writes.
$ErrorActionPreference='Stop'
$cameraBytes=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Source).Path)
$cameraHash=(Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
$cameraSum=0L
foreach($cameraByte in $cameraBytes){$cameraSum+=$cameraByte}
$cameraSum=$cameraSum -band 0xffffffffL
$cameraCode=@'
import board,microcontroller,binascii,usb_cdc,supervisor,displayio,digitalio,time
assert board.board_id=='greybadge'
assert binascii.hexlify(microcontroller.cpu.uid)==b'335cfeb138350510'
supervisor.runtime.autoreload=False
size=UPLOAD_SIZE
expected=EXPECTED_HASH
expected_sum=EXPECTED_SUM
old_timeout=usb_cdc.console.timeout
displayio.release_displays()
import hardware.fpga
reset_pin=digitalio.DigitalInOut(board.GP20)
try:
    reset_pin.switch_to_output(value=False)
    time.sleep(0.1)
    reset_pin.value=True
finally:
    reset_pin.deinit()
class SerialBitstream:
    def __init__(self):
        self.remaining=size
        self.checksum=0
    def readinto(self,target):
        if not self.remaining: return 0
        count=min(len(target),self.remaining)
        print('UPLOAD_BLOCK',count)
        line=usb_cdc.console.readline()
        assert line is not None,'Serial timeout'
        block=binascii.unhexlify(line.strip())
        assert len(block)==count,'Block length'
        target[:count]=block
        self.checksum=(self.checksum+sum(block))&0xffffffff
        self.remaining-=count
        return count
try:
    usb_cdc.console.timeout=15
    source=SerialBitstream()
    hardware.fpga.ecp5p.prog_stream(source,blocksize=4096)
    assert source.remaining==0 and source.checksum==expected_sum,'Stream checksum'
    ok=hardware.fpga.ecp5p.prog_close()
    print('FPGA_PROGRAM_VERIFIED',ok)
    assert ok,'FPGA configuration failed'
    print('UPLOAD_VERIFIED',size,'SUM32',source.checksum,'HOST_SOURCE_SHA256',expected)
finally:
    usb_cdc.console.timeout=old_timeout
'@
$cameraCode=$cameraCode.Replace('UPLOAD_SIZE',[string]$cameraBytes.Length).Replace('EXPECTED_HASH',"'$cameraHash'").Replace('EXPECTED_SUM',[string]$cameraSum)
if($ProbePanel) {
    $cameraDemoRoot=Split-Path -Parent $PSScriptRoot
    $cameraCode+="`ntime.sleep(1)`n"+[IO.File]::ReadAllText((Join-Path $cameraDemoRoot 'badge\sniff_panel.py'))
}
$cameraSerial=[IO.Ports.SerialPort]::new($Port,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$cameraSerial.DtrEnable=$true
$cameraSerial.WriteTimeout=15000
$script:uploadBuffer=''
function Read-UploadUntil([string]$Marker,[int]$Seconds=30) {
    $cameraDeadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    while([DateTime]::UtcNow -lt $cameraDeadline) {
        $script:uploadBuffer+=$cameraSerial.ReadExisting()
        if($Marker -eq 'UPLOAD_BLOCK ' -and $script:uploadBuffer.Contains([string][char]4)) {
            throw "Device upload error: $script:uploadBuffer"
        }
        $cameraAt=$script:uploadBuffer.IndexOf($Marker,[StringComparison]::Ordinal)
        if($cameraAt -ge 0) {
            $cameraResult=$script:uploadBuffer.Substring(0,$cameraAt)
            $script:uploadBuffer=$script:uploadBuffer.Substring($cameraAt+$Marker.Length)
            return $cameraResult
        }
        Start-Sleep -Milliseconds 5
    }
    throw "Upload timeout waiting for $Marker; received: $script:uploadBuffer"
}
try {
    $cameraSerial.Open()
    $cameraSerial.Write([byte[]](13,3,3),0,3)
    Start-Sleep -Milliseconds 400
    $cameraSerial.Write([byte[]](2,13,3),0,3)
    Start-Sleep -Milliseconds 400
    $null=$cameraSerial.ReadExisting()
    $cameraSerial.Write([byte[]](1),0,1)
    $null=Read-UploadUntil "raw REPL; CTRL-B to exit`r`n>" 5
    $cameraSerial.Write([byte[]](4),0,1)
    $null=Read-UploadUntil "raw REPL; CTRL-B to exit`r`n>" 10
    $cameraProgram=[Text.Encoding]::UTF8.GetBytes($cameraCode.Replace("`r`n","`n"))
    for($cameraOffset=0;$cameraOffset -lt $cameraProgram.Length;$cameraOffset+=128) {
        $cameraCount=[Math]::Min(128,$cameraProgram.Length-$cameraOffset)
        $cameraSerial.Write($cameraProgram,$cameraOffset,$cameraCount)
        Start-Sleep -Milliseconds 10
    }
    $cameraSerial.Write([byte[]](4),0,1)
    $null=Read-UploadUntil 'OK' 5
    for($cameraOffset=0;$cameraOffset -lt $cameraBytes.Length;$cameraOffset+=4096) {
        $null=Read-UploadUntil 'UPLOAD_BLOCK '
        $cameraRequested=[int](Read-UploadUntil "`n")
        $cameraCount=[Math]::Min(4096,$cameraBytes.Length-$cameraOffset)
        if($cameraRequested -ne $cameraCount){throw 'Unexpected upload block size'}
        $cameraHex=[BitConverter]::ToString($cameraBytes,$cameraOffset,$cameraCount).Replace('-','')+"`n"
        $cameraSerial.Write($cameraHex)
    }
    $cameraOut=Read-UploadUntil ([string][char]4)
    $cameraErr=Read-UploadUntil ([string][char]4) 5
    $null=Read-UploadUntil '>' 5
    Write-Output $cameraOut
    if($cameraErr){throw $cameraErr}
    if(-not $cameraOut.Contains('UPLOAD_VERIFIED')){throw 'No upload verification'}
} finally {
    if($cameraSerial.IsOpen) {
        try {$cameraSerial.Write([byte[]](3,2),0,2)} catch {}
        $cameraSerial.Close()
    }
    $cameraSerial.Dispose()
}
