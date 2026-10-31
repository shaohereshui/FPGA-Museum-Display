param([string]$ModelSimBin='D:/modelsim_ase/win32aloem')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$project=Join-Path $root 'projects/tf_sdram_hdmi_media_extension_candidate'
$evidence=Join-Path $root 'evidence'
Push-Location $evidence
try {
    if(-not (Test-Path -LiteralPath 'admin_work')) {
        & "$ModelSimBin/vlib.exe" admin_work
        if($LASTEXITCODE -ne 0){throw 'ModelSim library creation failed'}
    }
    $files=@('subtitle_uart.v','museum_subtitle.v','media_control.v','image_select_control.v','key_debounce.v') | ForEach-Object {Join-Path $project $_}
    & "$ModelSimBin/vlog.exe" -sv -work admin_work "+incdir+$project" @files (Join-Path $evidence 'tb_admin_control.sv')
    if($LASTEXITCODE -ne 0){throw 'Admin RTL compilation failed'}
    $output=& "$ModelSimBin/vsim.exe" -c -lib admin_work -l admin_control.log -wlf admin_control.wlf tb_admin_control -do 'run -all; quit -code 0' 2>&1
    $exitCode=$LASTEXITCODE
    $output | Write-Output
    $text=$output -join "`n"
    if($exitCode -ne 0 -or $text -notmatch 'PASS:' -or $text -match '\*\* (Fatal|Error):'){throw 'Admin control simulation failed'}
} finally {Pop-Location}
