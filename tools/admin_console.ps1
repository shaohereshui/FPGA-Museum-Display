param(
    [string]$RenderText = '',
    [string]$PacketOutput = '',
    [string]$PreviewOutput = '',
    [switch]$ClearPacket,
    [switch]$LibraryOnly,
    [string]$PortName = '',
    [switch]$AutoConnect
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-SubtitlePacket([string]$Text) {
    if ($Text.Length -gt 64) { throw '最多输入 64 个字符，请分成几次发送。' }
    if ($Text -match '[\r\n]') { throw '字幕为单行，请删除换行。' }
    foreach ($ch in $Text.ToCharArray()) {
        if ([char]::IsSurrogate($ch) -or [char]::IsControl($ch)) {
            throw '支持中文、英文、数字和常用标点；暂不支持 emoji 或控制字符。'
        }
    }
    $body = New-Object 'System.Collections.Generic.List[byte]'
    $body.Add([byte]$Text.Length)
    $font = New-Object System.Drawing.Font('Microsoft YaHei', 15, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    $fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap
    try {
        foreach ($ch in $Text.ToCharArray()) {
            $bitmap = New-Object System.Drawing.Bitmap(16, 16)
            $g = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $g.Clear([System.Drawing.Color]::Black)
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
                $g.DrawString([string]$ch, $font, [System.Drawing.Brushes]::White, [single]0, [single]-2, $fmt)
                for ($y=0; $y -lt 16; $y++) {
                    for ($half=0; $half -lt 2; $half++) {
                        $value=0
                        for ($x=0; $x -lt 8; $x++) {
                            if ($bitmap.GetPixel($half*8+$x,$y).R -ge 100) { $value=$value -bor (1 -shl (7-$x)) }
                        }
                        $body.Add([byte]$value)
                    }
                }
            } finally { $g.Dispose(); $bitmap.Dispose() }
        }
    } finally { $font.Dispose(); $fmt.Dispose() }
    $crc=65535
    foreach ($b in $body) {
        $crc=$crc -bxor ([int]$b -shl 8)
        for ($bit=0; $bit -lt 8; $bit++) {
            if (($crc -band 32768) -ne 0) { $crc=(($crc -shl 1) -bxor 4129) -band 65535 }
            else { $crc=($crc -shl 1) -band 65535 }
        }
    }
    $packet=New-Object 'System.Collections.Generic.List[byte]'
    $packet.AddRange([byte[]]@(165,90,1))
    $packet.AddRange($body.ToArray())
    $packet.Add([byte]($crc -shr 8)); $packet.Add([byte]($crc -band 255))
    return ,($packet.ToArray())
}

# Headless mode generates the exact GUI packet for tests; it never opens a port.
if ($PacketOutput) {
    $payloadText = if ($ClearPacket) { '' } else { $RenderText }
    [System.IO.File]::WriteAllBytes([System.IO.Path]::GetFullPath($PacketOutput), (Get-SubtitlePacket $payloadText))
    Write-Output '已生成字幕数据包，未打开串口。'
    return
}

function Get-ProtocolCrc([byte[]]$Bytes) {
    $crc=65535
    foreach($b in $Bytes) {
        $crc=$crc -bxor ([int]$b -shl 8)
        for($bit=0;$bit -lt 8;$bit++) {
            if($crc -band 32768){$crc=(($crc -shl 1) -bxor 4129) -band 65535}
            else {$crc=($crc -shl 1) -band 65535}
        }
    }
    return $crc
}
function Get-ControlPacket([byte]$Command,[byte]$Value=0) {
    $valid=switch($Command) {
        {$_ -in 2,37,38} {$Value -eq 0}
        32 {$Value -lt 5}
        33 {$Value -le 100}
        34 {($Value -le 9) -or ($Value -eq 255)}
        35 {$Value -le 9}
        {$_ -in 36,40,41} {$Value -le 1}
        39 {$Value -le 2}
        default {$false}
    }
    if(-not $valid){throw ('命令或参数超出范围：0x{0:X2} / {1}' -f $Command,$Value)}
    $crc=Get-ProtocolCrc ([byte[]]@($Command,$Value))
    return ,([byte[]]@(165,90,$Command,$Value,($crc -shr 8),($crc -band 255)))
}
function ConvertFrom-BoardReply([byte[]]$Reply) {
    if($Reply.Length -ne 15 -or $Reply[0] -ne 6){throw '板卡状态应答长度或 ACK 错误。'}
    $crc=Get-ProtocolCrc $Reply[1..12]
    if($crc -ne (([int]$Reply[13] -shl 8) -bor $Reply[14])){throw '板卡状态 CRC 校验失败。'}
    if($Reply[1] -ne 2){throw ('固件协议版本不匹配：{0}，需要协议版本 2 的管理固件。' -f $Reply[1])}
    if($Reply[2] -gt 4 -or $Reply[3] -gt 4 -or $Reply[4] -gt 100 -or
       $Reply[5] -gt 9 -or $Reply[6] -gt 9 -or $Reply[8] -gt 15 -or
       $Reply[10] -gt 2 -or $Reply[11] -gt 1){throw '板卡状态字段超出协议范围。'}
    $flags=$Reply[7]
    return [pscustomobject]@{
        Image=[int]$Reply[2]+1;RequestedImage=[int]$Reply[3]+1;Volume=[int]$Reply[4]
        Brightness=[int]$Reply[5];Contrast=[int]$Reply[6];Manual=[bool]($flags -band 1)
        Carousel=[bool]($flags -band 2);AudioEnabled=[bool]($flags -band 4)
        Ready=[bool]($flags -band 8);Fault=[bool]($flags -band 16);Zoom=[bool]($flags -band 32)
        AudioPaused=[bool]($flags -band 64);LightValid=[bool]($flags -band 128)
        Adc=([int]$Reply[8] -shl 8) -bor $Reply[9];Transition=[int]$Reply[10]
        Visual=[int]$Reply[11];FaultCode=[int]$Reply[12]
    }
}
function Open-BoardPort([string]$Name) {
    $port=New-Object System.IO.Ports.SerialPort($Name,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
    $port.ReadTimeout=3000;$port.WriteTimeout=3000;$port.DtrEnable=$false;$port.RtsEnable=$false
    try {$port.Open();$port.DiscardInBuffer();return $port}
    catch {$port.Dispose();throw}
}
function Invoke-BoardPacket($Port,[byte[]]$Packet,[switch]$Control) {
    if(-not $Port -or -not $Port.IsOpen){throw '串口尚未连接。'}
    $Port.Write($Packet,0,$Packet.Length)
    $answer=$Port.ReadByte()
    if($answer -ne 6){throw ('板卡拒绝命令：0x{0:X2}，请核对当前固件和参数。' -f $answer)}
    if($Control) {
        $reply=New-Object byte[] 15;$reply[0]=6
        for($i=1;$i -lt 15;$i++){$reply[$i]=[byte]$Port.ReadByte()}
        return ConvertFrom-BoardReply $reply
    }
}
function Invoke-BoardControl($Port,[byte]$Command,[byte]$Value=0) {
    return Invoke-BoardPacket $Port (Get-ControlPacket $Command $Value) -Control
}
if($LibraryOnly){return}

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:serial=$null;$script:applyingState=$false;$script:lastBoardState=$null
$form=New-Object System.Windows.Forms.Form
$form.Text='知古博物馆 · 管理控制台 v49'
$form.ClientSize=New-Object System.Drawing.Size(800,600)
$form.FormBorderStyle='FixedSingle';$form.MaximizeBox=$false;$form.StartPosition='CenterScreen'
$form.Font=New-Object System.Drawing.Font('Microsoft YaHei',10)
$form.BackColor=[System.Drawing.Color]::White
$tips=New-Object System.Windows.Forms.ToolTip
function Add-Label($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W=150,[int]$H=26) {
    $c=New-Object System.Windows.Forms.Label;$c.Text=$Text
    $c.Location=New-Object System.Drawing.Point($X,$Y);$c.Size=New-Object System.Drawing.Size($W,$H)
    $Parent.Controls.Add($c);return $c
}
function Add-Button($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W=96) {
    $c=New-Object System.Windows.Forms.Button;$c.Text=$Text
    $c.Location=New-Object System.Drawing.Point($X,$Y);$c.Size=New-Object System.Drawing.Size($W,34)
    $Parent.Controls.Add($c);return $c
}
function Add-Combo($Parent,[string[]]$Items,[int]$X,[int]$Y,[int]$W=130) {
    $c=New-Object System.Windows.Forms.ComboBox;$c.DropDownStyle='DropDownList'
    $c.Location=New-Object System.Drawing.Point($X,$Y);$c.Size=New-Object System.Drawing.Size($W,30)
    $c.Items.AddRange([object[]]$Items);if($Items.Count){$c.SelectedIndex=0}
    $Parent.Controls.Add($c);return $c
}
function Add-Number($Parent,[int]$Maximum,[int]$Value,[int]$X,[int]$Y) {
    $c=New-Object System.Windows.Forms.NumericUpDown;$c.Minimum=0;$c.Maximum=$Maximum;$c.Value=$Value
    $c.Location=New-Object System.Drawing.Point($X,$Y);$c.Size=New-Object System.Drawing.Size(80,30)
    $Parent.Controls.Add($c);return $c
}
function Add-Check($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W=150) {
    $c=New-Object System.Windows.Forms.CheckBox;$c.Text=$Text
    $c.Location=New-Object System.Drawing.Point($X,$Y);$c.Size=New-Object System.Drawing.Size($W,30)
    $Parent.Controls.Add($c);return $c
}
[void](Add-Label $form '知古博物馆' 20 15 210 34)
$form.Controls[0].Font=New-Object System.Drawing.Font('Microsoft YaHei',16,[System.Drawing.FontStyle]::Bold)
[void](Add-Label $form '串口' 298 23 45)
$ports=Add-Combo $form @() 346 18 112
$refresh=Add-Button $form '刷新' 470 15 74
$connect=Add-Button $form '连接' 556 15 94
$connection=Add-Label $form '未连接' 665 23 115
$telemetry=Add-Label $form '等待连接板卡' 20 67 760 56
$telemetry.BackColor=[System.Drawing.Color]::FromArgb(240,244,246)
$telemetry.Padding=New-Object System.Windows.Forms.Padding(10,6,10,0)
$panel=New-Object System.Windows.Forms.Panel
$panel.Location=New-Object System.Drawing.Point(20,136);$panel.Size=New-Object System.Drawing.Size(760,392)
$panel.Enabled=$false;$form.Controls.Add($panel)
[void](Add-Label $panel '画面' 0 0 80)
$previous=Add-Button $panel '上一张' 100 0
$next=Add-Button $panel '下一张' 208 0
$imageChoice=Add-Combo $panel @('第 1 张','第 2 张','第 3 张','第 4 张','第 5 张') 328 3 115
$selectImage=Add-Button $panel '切换' 455 0 80
$carousel=Add-Check $panel '自动轮播' 558 2
[void](Add-Label $panel '音量' 0 58 80)
$volumeInput=Add-Number $panel 100 50 100 54
[void](Add-Label $panel '%' 185 58 24)
$setVolume=Add-Button $panel '设置音量' 218 51 110
$pauseAudio=Add-Check $panel '暂停音频' 356 53
$audioState=Add-Label $panel '' 558 58 195
[void](Add-Label $panel '亮度' 0 111 80)
$brightnessInput=Add-Number $panel 9 5 100 107
$setBrightness=Add-Button $panel '设置亮度' 218 104 110
$autoLight=Add-Check $panel '光敏自动' 356 106
[void](Add-Label $panel '对比度' 0 164 80)
$contrastInput=Add-Number $panel 9 5 100 160
$setContrast=Add-Button $panel '设置对比度' 218 157 110
[void](Add-Label $panel '转场' 356 164 50)
$transitionChoice=Add-Combo $panel @('四角展开','滑动','淡入淡出') 412 160 130
[void](Add-Label $panel '可视化' 560 164 65)
$visualChoice=Add-Combo $panel @('频谱','波形') 630 160 126
[void](Add-Label $panel '公告字幕' 0 218 110)
$entry=New-Object System.Windows.Forms.TextBox;$entry.MaxLength=64;$entry.Text='欢迎来到知古博物馆'
$entry.Location=New-Object System.Drawing.Point(0,250);$entry.Size=New-Object System.Drawing.Size(756,30)
$panel.Controls.Add($entry)
$send=Add-Button $panel '发送字幕' 0 296 125
$clear=Add-Button $panel '恢复欢迎字幕' 139 296 145
$import=Add-Button $panel '导入文本' 298 296 125
$readState=Add-Button $panel '读取状态' 630 296 126
$status=Add-Label $form '尚未连接' 20 540 760 46
$tips.SetToolTip($autoLight,'取消勾选将使用左侧亮度值；手动设置约 30 秒无操作后恢复光敏自动。')
$tips.SetToolTip($pauseAudio,'板载开关或遥控器暂停仍然有效；实际音频状态显示在右侧。')
$tips.SetToolTip($entry,'最多 64 个字符')
$timer=New-Object System.Windows.Forms.Timer;$timer.Interval=1000
function Update-BoardState($s) {
    $script:lastBoardState=$s;$script:applyingState=$true
    try {
        $mode=if($s.Manual){'手动'}else{'自动'}
        $ready=if($s.Fault){'故障 '+$s.FaultCode}elseif($s.Ready){'就绪'}else{'加载中'}
        $telemetry.Text=('当前图 {0}   /   请求图 {1}     音量 {2}%     亮度 {3}（{4}）     对比度 {5}' -f $s.Image,$s.RequestedImage,$s.Volume,$s.Brightness,$mode,$s.Contrast)+"`r`n"+('板卡：{0}     最近回读 {1}' -f $ready,(Get-Date -Format 'HH:mm:ss'))
        $telemetry.ForeColor=if($s.Fault){[System.Drawing.Color]::Firebrick}else{[System.Drawing.Color]::FromArgb(25,45,50)}
        if(-not $volumeInput.ContainsFocus){$volumeInput.Value=$s.Volume}
        if(-not $brightnessInput.ContainsFocus){$brightnessInput.Value=$s.Brightness}
        if(-not $contrastInput.ContainsFocus){$contrastInput.Value=$s.Contrast}
        if(-not $imageChoice.ContainsFocus){$imageChoice.SelectedIndex=$s.RequestedImage-1}
        $carousel.Checked=$s.Carousel;$pauseAudio.Checked=$s.AudioPaused;$autoLight.Checked=-not $s.Manual
        if(-not $transitionChoice.ContainsFocus){$transitionChoice.SelectedIndex=$s.Transition}
        if(-not $visualChoice.ContainsFocus){$visualChoice.SelectedIndex=$s.Visual}
        $audioState.Text=if($s.AudioEnabled){'音频：播放'}else{'音频：暂停'}
    } finally {$script:applyingState=$false}
}
function Disconnect-Board {
    $timer.Stop()
    if($script:serial){try {$script:serial.Close()} finally {$script:serial.Dispose();$script:serial=$null}}
    $panel.Enabled=$false;$ports.Enabled=$true;$refresh.Enabled=$true;$connect.Text='连接'
    $connection.Text='未连接';$telemetry.Text='板卡状态已停止更新'
}
function Report-ConnectionError($ErrorRecord) {
    Disconnect-Board
    $status.ForeColor=[System.Drawing.Color]::Firebrick
    $status.Text='通信失败：'+$ErrorRecord.Exception.Message
}
function Send-Control([byte]$Command,[byte]$Value,[string]$Description) {
    if($script:applyingState){return}
    try {
        Update-BoardState (Invoke-BoardControl $script:serial $Command $Value)
        $status.ForeColor=[System.Drawing.Color]::DarkGreen
        $status.Text='板卡已确认：'+$Description
    } catch {Report-ConnectionError $_}
}
$refreshAction={
    $selected=[string]$ports.SelectedItem;$ports.Items.Clear()
    foreach($name in [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object){[void]$ports.Items.Add($name)}
    $desired=if($PortName){$PortName}else{$selected}
    if($ports.Items.Contains($desired)){$ports.SelectedItem=$desired}
    elseif($ports.Items.Count){$ports.SelectedIndex=0}
}
$refresh.Add_Click($refreshAction)
$connectAction={
    if($script:serial){Disconnect-Board;$status.Text='已断开连接';return}
    try {
        if(-not $ports.SelectedItem){throw '没有可用串口，请连接板载 Type-C 后刷新。'}
        $script:serial=Open-BoardPort ([string]$ports.SelectedItem)
        Update-BoardState (Invoke-BoardControl $script:serial 2 0)
        $panel.Enabled=$true;$ports.Enabled=$false;$refresh.Enabled=$false;$connect.Text='断开'
        $connection.Text=[string]$ports.SelectedItem+' · 已连接'
        $status.ForeColor=[System.Drawing.Color]::DarkGreen;$status.Text='板卡已确认：管理连接已建立。'
        $timer.Start()
    } catch {Report-ConnectionError $_}
}
$connect.Add_Click($connectAction)
$previous.Add_Click({Send-Control 37 0 '上一张'})
$next.Add_Click({Send-Control 38 0 '下一张'})
$selectImage.Add_Click({Send-Control 32 ([byte]$imageChoice.SelectedIndex) ('请求第 '+($imageChoice.SelectedIndex+1)+' 张')})
$carousel.Add_CheckedChanged({Send-Control 36 ([byte][int]$carousel.Checked) '轮播设置'})
$setVolume.Add_Click({Send-Control 33 ([byte]$volumeInput.Value) '音量设置'})
$setBrightness.Add_Click({Send-Control 34 ([byte]$brightnessInput.Value) '手动亮度设置'})
$autoLight.Add_CheckedChanged({$value=if($autoLight.Checked){255}else{[byte]$brightnessInput.Value};Send-Control 34 $value '亮度模式设置'})
$setContrast.Add_Click({Send-Control 35 ([byte]$contrastInput.Value) '对比度设置'})
$pauseAudio.Add_CheckedChanged({Send-Control 41 ([byte][int]$pauseAudio.Checked) '音频暂停设置'})
$transitionChoice.Add_SelectionChangeCommitted({Send-Control 39 ([byte]$transitionChoice.SelectedIndex) '转场设置'})
$visualChoice.Add_SelectionChangeCommitted({Send-Control 40 ([byte]$visualChoice.SelectedIndex) '可视化设置'})
$readState.Add_Click({Send-Control 2 0 '状态已更新'})
$timer.Add_Tick({try {Update-BoardState (Invoke-BoardControl $script:serial 2 0)} catch {Report-ConnectionError $_}})
$transmit={
    param([string]$message)
    try {$packet=Get-SubtitlePacket $message}
    catch {$status.ForeColor=[System.Drawing.Color]::Firebrick;$status.Text='字幕输入错误：'+$_.Exception.Message;return}
    try {
        Invoke-BoardPacket $script:serial $packet
        $status.ForeColor=[System.Drawing.Color]::DarkGreen
        $status.Text=if($message.Length){'板卡已确认：新字幕已生效。'}else{'板卡已确认：恢复默认欢迎字幕。'}
    } catch {Report-ConnectionError $_}
}
$send.Add_Click({& $transmit $entry.Text});$clear.Add_Click({& $transmit ''})
$import.Add_Click({
    $dialog=New-Object System.Windows.Forms.OpenFileDialog;$dialog.Filter='UTF-8 文本 (*.txt)|*.txt'
    try {
        if($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $text=[System.IO.File]::ReadAllText($dialog.FileName,(New-Object System.Text.UTF8Encoding($false,$true)))
            $text=$text.Trim().Replace("`r",' ').Replace("`n",' ')
            if($text.Length -gt 64){throw '文件超过 64 个字符。'}
            $entry.Text=$text
        }
    } catch {$status.ForeColor=[System.Drawing.Color]::Firebrick;$status.Text='导入失败：'+$_.Exception.Message}
    finally {$dialog.Dispose()}
})
$form.Add_FormClosing({Disconnect-Board})
& $refreshAction
if($AutoConnect){$form.Add_Shown($connectAction)}
try {
    if($PreviewOutput) {
        $form.ShowInTaskbar=$false;$form.Show();[System.Windows.Forms.Application]::DoEvents()
        $canvas=New-Object System.Drawing.Bitmap($form.Width,$form.Height)
        try {$form.DrawToBitmap($canvas,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)));$canvas.Save([System.IO.Path]::GetFullPath($PreviewOutput),[System.Drawing.Imaging.ImageFormat]::Png)}
        finally {$canvas.Dispose()}
    } else {[void]$form.ShowDialog()}
} finally {Disconnect-Board;$timer.Dispose();$tips.Dispose();$form.Dispose()}
