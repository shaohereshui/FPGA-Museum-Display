$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'admin_console.ps1') -LibraryOnly
function Assert-Throws([scriptblock]$Action,[string]$Message) {
    $threw=$false
    try {& $Action} catch {$threw=$true}
    if(-not $threw){throw $Message}
}
if((Get-ProtocolCrc ([Text.Encoding]::ASCII.GetBytes('123456789'))) -ne 0x29b1){throw 'CRC reference vector failed'}
if([BitConverter]::ToString((Get-SubtitlePacket '')) -ne 'A5-5A-01-00-E1-F0'){throw 'Existing subtitle clear frame changed'}
$glyph=Get-SubtitlePacket '上位机测试123'
if($glyph.Length -ne (6+8*32) -or $glyph[3] -ne 8){throw 'Chinese glyph packet failed'}
$crc=Get-ProtocolCrc $glyph[3..($glyph.Length-3)]
if($crc -ne (([int]$glyph[-2] -shl 8) -bor $glyph[-1])){throw 'Glyph CRC failed'}
foreach($case in @(@(2,0),@(32,4),@(33,100),@(34,9),@(34,255),@(35,9),@(36,1),@(37,0),@(38,0),@(39,2),@(40,1),@(41,1))) {
    $packet=Get-ControlPacket $case[0] $case[1]
    if($packet.Length -ne 6 -or $packet[2] -ne $case[0] -or $packet[3] -ne $case[1]){throw 'Control packet fields failed'}
    if((Get-ProtocolCrc $packet[2..3]) -ne (([int]$packet[4] -shl 8) -bor $packet[5])){throw 'Control CRC failed'}
}
Assert-Throws {Get-ControlPacket 32 5} 'Invalid image accepted'
Assert-Throws {Get-ControlPacket 33 101} 'Invalid volume accepted'
Assert-Throws {Get-ControlPacket 34 10} 'Invalid brightness accepted'
Assert-Throws {Get-ControlPacket 42 0} 'Unsupported command accepted'
Assert-Throws {Get-SubtitlePacket ('a'*65)} 'Oversize text accepted'
$payload=[byte[]]@(2,4,3,73,6,4,143,12,52,2,1,0)
$crc=Get-ProtocolCrc $payload
$reply=[byte[]](@(6)+$payload+@(($crc -shr 8),($crc -band 255)))
$s=ConvertFrom-BoardReply $reply
if($s.Image -ne 5 -or $s.RequestedImage -ne 4 -or $s.Volume -ne 73 -or $s.Adc -ne 3124 -or -not $s.Manual -or -not $s.LightValid){throw 'Status decoding failed'}
$bad=$reply.Clone();$bad[4]=$bad[4] -bxor 1
Assert-Throws {ConvertFrom-BoardReply $bad} 'Corrupt status accepted'
$bad=$reply.Clone();$bad[1]=1;$crc=Get-ProtocolCrc $bad[1..12];$bad[13]=$crc -shr 8;$bad[14]=$crc -band 255
Assert-Throws {ConvertFrom-BoardReply $bad} 'Wrong firmware version accepted'
'PASS: host CRC reference vector, Chinese glyphs, command ranges, status decoding and corrupt/version rejection'
