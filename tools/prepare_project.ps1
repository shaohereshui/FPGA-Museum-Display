param([string]$Destination = '')
$ErrorActionPreference = 'Stop'
$bundleRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $bundleRoot ('build_workspace_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$preparedRoot = [System.IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $preparedRoot) { throw "Destination already exists: $preparedRoot" }
New-Item -ItemType Directory -Path $preparedRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $bundleRoot 'projects') -Destination $preparedRoot -Recurse
$projectDir = Join-Path $preparedRoot 'projects/tf_sdram_hdmi_media_extension_candidate'
$projectFile = Join-Path $projectDir 'tf_sdram_hdmi_media_extension_candidate.al'
# TD accepts its original unescaped UsedInP&R attribute value. Normalize that
# value for the XML parser while relocating only this disposable project copy.
$xmlText = [System.IO.File]::ReadAllText($projectFile).Replace('UsedInP&R','UsedInP&amp;R')
[xml]$projectXml = $xmlText
$projectXml.Project.SetAttribute('Path', $projectDir.Replace('\','/'))
$writerSettings = New-Object System.Xml.XmlWriterSettings
$writerSettings.Indent = $true
$writerSettings.Encoding = New-Object System.Text.UTF8Encoding($false)
$xmlWriter = [System.Xml.XmlWriter]::Create($projectFile, $writerSettings)
try { $projectXml.Save($xmlWriter) } finally { $xmlWriter.Dispose() }
foreach ($file in $projectXml.SelectNodes('//Source_Files//File')) {
    $referenced = [System.IO.Path]::GetFullPath((Join-Path $projectDir $file.Path))
    if (-not (Test-Path -LiteralPath $referenced -PathType Leaf)) {
        throw "Project dependency missing: $referenced"
    }
}
Write-Output $projectDir
