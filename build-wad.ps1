$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$staging = Join-Path $env:TEMP 'universal_tacticool_staging'
$wadName = '08 Universal_Tacticool.wad'
$wadPath = Join-Path $projectRoot $wadName

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
New-Item -ItemType Directory -Path (Join-Path $staging 'ZSCRIPT') | Out-Null

$files = @(
    'CVARINFO.txt',
    'KEYCONF.txt',
    'LANGUAGE.txt',
    'LICENSE',
    'MENUDEF.txt',
    'README.md',
    'ZMAPINFO.txt',
    'ZSCRIPT.zs'
)
foreach ($file in $files) {
    Copy-Item (Join-Path $projectRoot $file) (Join-Path $staging $file)
}
Copy-Item (Join-Path $projectRoot 'ZSCRIPT\*') (Join-Path $staging 'ZSCRIPT') -Recurse

if (Test-Path $wadPath) { Remove-Item $wadPath -Force }
$zip = [System.IO.Compression.ZipFile]::Open($wadPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $staging -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($staging.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $relative) | Out-Null
    }
}
finally {
    $zip.Dispose()
}

$targets = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\(Doom Mod Builds)\.ADDONSs\(UNIVERSAL_DASH_GORE_KICK_TILT)\08 Universal_Tacticool.wad'
)

$bundleZips = @(
    '(UNIVERSAL_DASH_GORE_KICK_TILT).zip',
    '(UNIVERSAL_DASH_GORE_TILT).zip',
    '(UNIVERSAL_DASH_KICK_TILT).zip',
    '(UNIVERSAL_GORE_TILT).zip',
    '(UNIVERSAL_TILT).zip'
)
$addonsRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\(Doom Mod Builds)\.ADDONSs'

foreach ($target in $targets) {
    Copy-Item $wadPath $target -Force
    Write-Output "Updated: $target"
}

function Update-WadInZip {
    param([string]$ZipPath, [string]$EntryName, [string]$SourceWad)
    $tempZip = "$ZipPath.tmp"
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    Copy-Item $ZipPath $tempZip
    $zip = [System.IO.Compression.ZipFile]::Open($tempZip, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $existing = $zip.GetEntry($EntryName)
        if ($existing) { $existing.Delete() }
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $SourceWad, $EntryName) | Out-Null
    }
    finally {
        $zip.Dispose()
    }
    Move-Item $tempZip $ZipPath -Force
}

foreach ($bundle in $bundleZips) {
    $zipPath = Join-Path $addonsRoot $bundle
    if (-not (Test-Path $zipPath)) { continue }
    Update-WadInZip -ZipPath $zipPath -EntryName $wadName -SourceWad $wadPath
    Write-Output "Updated bundle: $bundle"
}

Write-Output "Built $wadPath ($((Get-Item $wadPath).Length) bytes)"
