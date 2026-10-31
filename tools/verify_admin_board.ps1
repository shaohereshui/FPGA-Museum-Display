param([string]$PortName='COM5',[string]$OutputPath='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'admin_console.ps1') -LibraryOnly -PortName $PortName
$results=New-Object 'System.Collections.Generic.List[object]'
$port=$null;$original=$null
function Check-State([bool]$Condition,[string]$Name,$State) {
    if(-not $Condition){throw "Board readback failed: $Name"}
    $results.Add([pscustomobject]@{test=$Name;passed=$true;state=$State})
    Write-Output "PASS: $Name"
}
function Wait-Image([int]$Image) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        $s=Invoke-BoardControl $port 2
        if($s.Image -eq $Image){return $s}
        Start-Sleep -Milliseconds 200
    } while($watch.Elapsed.TotalSeconds -lt 12)
    throw "Displayed image did not reach $Image (board reports $($s.Image), requested $($s.RequestedImage))"
}
try {
    $port=Open-BoardPort $PortName
    $original=Invoke-BoardControl $port 2
    Check-State ($original.Ready -and -not $original.Fault) 'ready and no active fault' $original
    $s=Invoke-BoardControl $port 36 0
    Check-State (-not $s.Carousel) 'pause carousel' $s
    [void](Invoke-BoardControl $port 39 0)
    for($i=0;$i -lt 5;$i++) {
        $s=Invoke-BoardControl $port 32 $i
        Check-State ($s.RequestedImage -eq $i+1) ('request image '+($i+1)) $s
        $s=Wait-Image ($i+1)
        Check-State ($s.Image -eq $i+1) ('display register image '+($i+1)) $s
    }
    $s=Invoke-BoardControl $port 38 0
    Check-State ($s.RequestedImage -eq 1) 'next image wraps 5 to 1' $s
    [void](Wait-Image 1)
    $s=Invoke-BoardControl $port 37 0
    Check-State ($s.RequestedImage -eq 5) 'previous image wraps 1 to 5' $s
    [void](Wait-Image 5)
    $s=Invoke-BoardControl $port 33 73
    Check-State ($s.Volume -eq 73) 'volume 73' $s
    $s=Invoke-BoardControl $port 34 6
    Check-State ($s.Brightness -eq 6 -and $s.Manual) 'manual brightness 6' $s
    $s=Invoke-BoardControl $port 35 4
    Check-State ($s.Contrast -eq 4) 'contrast 4' $s
    $s=Invoke-BoardControl $port 34 255
    Check-State (-not $s.Manual -and $s.LightValid) 'restore automatic light mode' $s
    foreach($mode in 0,1,2) {
        $s=Invoke-BoardControl $port 39 $mode
        Check-State ($s.Transition -eq $mode) "transition $mode" $s
    }
    foreach($mode in 0,1) {
        $s=Invoke-BoardControl $port 40 $mode
        Check-State ($s.Visual -eq $mode) "visual mode $mode" $s
    }
    $s=Invoke-BoardControl $port 41 1
    Check-State ($s.AudioPaused -and -not $s.AudioEnabled) 'pause audio' $s
    $s=Invoke-BoardControl $port 41 0
    Check-State (-not $s.AudioPaused) 'release host audio pause (physical switch remains authoritative)' $s
    $s=Invoke-BoardControl $port 36 1
    $before=$s.RequestedImage
    Start-Sleep -Milliseconds 5500
    $s=Invoke-BoardControl $port 2
    Check-State ($s.Carousel -and $s.RequestedImage -ne $before) 'carousel advances' $s
    Invoke-BoardPacket $port (Get-SubtitlePacket '上位机控制测试')
    Check-State $true 'Chinese subtitle frame-boundary ACK' $null
} finally {
    if($port) {
        try {
            if($original) {
                [void](Invoke-BoardControl $port 36 0)
                [void](Invoke-BoardControl $port 32 ($original.RequestedImage-1))
                [void](Invoke-BoardControl $port 33 $original.Volume)
                [void](Invoke-BoardControl $port 35 $original.Contrast)
                $value=if($original.Manual){$original.Brightness}else{255}
                [void](Invoke-BoardControl $port 34 $value)
                [void](Invoke-BoardControl $port 39 $original.Transition)
                [void](Invoke-BoardControl $port 40 $original.Visual)
                [void](Invoke-BoardControl $port 41 ([byte][int]$original.AudioPaused))
                [void](Invoke-BoardControl $port 36 ([byte][int]$original.Carousel))
            }
        } finally {$port.Close();$port.Dispose()}
    }
}
if($OutputPath) {
    [ordered]@{timestamp=(Get-Date).ToString('o');port=$PortName;tests=$results.ToArray();original_state=$original;
        original_controls_restored=$true;screen_observation_confirmed=$false;
        analog_response_rechecked=$false;flash_written=$false} |
        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
