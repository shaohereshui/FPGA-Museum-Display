param(
    [string]$TdExe = 'D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',
    [string]$PreparedProject = '',
    [switch]$ElaborateOnly
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TdExe -PathType Leaf)) { throw "Set -TdExe to your TD 6.2.1 executable: $TdExe" }
$resolvedTd = (Resolve-Path -LiteralPath $TdExe).Path
if ([string]::IsNullOrWhiteSpace($PreparedProject)) {
    $PreparedProject = & (Join-Path $PSScriptRoot 'prepare_project.ps1')
}
$projectDir = (Resolve-Path -LiteralPath $PreparedProject).Path
$scriptName = 'build.tcl'
if ($ElaborateOnly) {
    $scriptName = 'bundle_elaborate.tcl'
    $elaborateTcl = @'
import_device eagle_s20.db -package EG4S20BG256
open_project tf_sdram_hdmi_media_extension_candidate.al -single_run
load_run_param -run syn_1
commit_param -step design
elaborate -top tf_sdram_hdmi_media_top
read_adc tf_sdram_hdmi_media_extension_candidate.adc
read_sdc tf_sdram_hdmi_media_extension_candidate.sdc
puts "BUNDLE_ELABORATION_PASSED"
exit
'@
    [System.IO.File]::WriteAllText((Join-Path $projectDir $scriptName),$elaborateTcl,(New-Object System.Text.UTF8Encoding($false)))
}
$logPath = Join-Path $projectDir $(if ($ElaborateOnly) {'bundle_elaborate.log'} else {'bundle_build.log'})
$startedAt = Get-Date
Push-Location $projectDir
try {
    & $resolvedTd $scriptName *> $logPath
    $tdExit = $LASTEXITCODE
    $logText = Get-Content -Raw -LiteralPath $logPath
    if ($tdExit -ne 0 -or $logText -match '(?m)\bERROR\s*:|invalid command|couldn''t read|couldn''t open|can''t read') {
        throw "TD failed; inspect $logPath"
    }
    if ($ElaborateOnly) {
        if ($logText -notmatch 'BUNDLE_ELABORATION_PASSED') { throw 'TD did not reach the elaboration completion marker' }
        Write-Output "PASS: relocated project elaboration; log: $logPath"
    } else {
        $timing = Get-Content -Raw -LiteralPath (Join-Path $projectDir 'media_phy.ts')
        foreach ($metric in @('SWNS','STNS','HWNS','HTNS')) {
            $match = [regex]::Match($timing,"${metric}:\s*(-?\d+(?:\.\d+)?)ns")
            if (-not $match.Success -or [double]$match.Groups[1].Value -lt 0) { throw "Timing failed: $metric ($timing)" }
        }
        $builtBit = Get-Item -LiteralPath (Join-Path $projectDir 'tf_sdram_hdmi_media_extension_candidate.bit')
        if ($builtBit.LastWriteTime -lt $startedAt) { throw 'No fresh bitstream generated' }
        if ($logText -notmatch 'Generate bits file tf_sdram_hdmi_media_extension_candidate.bit') { throw 'Missing bitgen completion marker' }
        $releaseDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'rebuilt_bitstream'
        New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
        Copy-Item -LiteralPath $builtBit.FullName -Destination (Join-Path $releaseDir 'fpga_museum_v47_board_controls.bit')
        Get-FileHash -Algorithm SHA256 -LiteralPath $builtBit.FullName
        Write-Output "PASS: local build and timing checks; output: $($builtBit.FullName)"
    }
} finally { Pop-Location }
# This script never opens BitWriter and never programs SRAM or Flash.
