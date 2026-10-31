param(
    [string]$ModelSimBin = 'D:/modelsim_ase/win32aloem',
    [string[]]$Tests = @('tb_adc_clock','tb_light_manual_timeout','tb_board_controls','tb_zoom_remote','tb_period','tb_menu_values')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'projects/tf_sdram_hdmi_media_extension_candidate'
$evidence = Join-Path $root 'evidence'
$sources = @('eg4_light_sensor.v','ambient_brightness.v','board_controls.v','media_control.v',
    'media_input_router.v','key_debounce.v','ir_nec_keys.v','hdmi_osd_5x7.v','museum_subtitle.v')
$testbenches = @('tb_adc_clock','tb_light_manual_timeout','tb_board_controls','tb_zoom_remote','tb_period','tb_menu_values')
$compileArgs = @('-sv','-work','work',('+incdir+'+$project))
foreach ($source in $sources) { $compileArgs += Join-Path $project $source }
foreach ($testbench in $testbenches) { $compileArgs += Join-Path $evidence ($testbench+'.sv') }
$results = @()
Push-Location $evidence
try {
    if (-not (Test-Path -LiteralPath 'work')) {
        & (Join-Path $ModelSimBin 'vlib.exe') work
        if ($LASTEXITCODE -ne 0) { throw 'ModelSim library creation failed.' }
    }
    & (Join-Path $ModelSimBin 'vlog.exe') @compileArgs
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim compilation failed.' }
    # This installation can return exit 0 on $fatal; require PASS and reject fatal output.
    foreach ($test in $Tests) {
        if ($test -notin $testbenches) { throw "Unknown test: $test" }
        $output = & (Join-Path $ModelSimBin 'vsim.exe') -c -lib work -l ($test+'_checked.log') -wlf ($test+'_checked.wlf') $test -do 'run -all; quit -code 0' 2>&1
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"
        $passLines = $output | Where-Object { $_ -match '\bPASS\b' }
        if ($exitCode -ne 0 -or -not $passLines -or $text -match '\*\* (Fatal|Error):') {
            $output | Write-Output
            throw "Simulation failed: $test"
        }
        $passLines | Write-Output
        $results += [pscustomobject]@{test=$test;passed=$true;log=($test+'_checked.log')}
    }
    [pscustomobject]@{
        time=(Get-Date -Format o)
        tests=$results
        analog_hardware_verified=$false
        flash_written=$false
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath 'adc_simulation_results.json'
} finally { Pop-Location }
