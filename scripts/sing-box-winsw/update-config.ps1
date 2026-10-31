param(
    [string]$BaseDirectory = $PSScriptRoot,
    [string]$PersistDirectory = (Join-Path $PSScriptRoot '..\..\..\persist\sing-box-winsw')
)

$ErrorActionPreference = 'Stop'
$urlFile = Join-Path $PersistDirectory 'config-url.txt'
$configFile = Join-Path $BaseDirectory 'config.json'
$persistConfig = Join-Path $PersistDirectory 'config.json'
$tempFile = Join-Path $PersistDirectory ('.config-' + [guid]::NewGuid().ToString('N') + '.json')
$installTemp = Join-Path $BaseDirectory ('.config-' + [guid]::NewGuid().ToString('N') + '.json')
$backupFile = Join-Path $PersistDirectory ('.config-backup-' + [guid]::NewGuid().ToString('N') + '.json')
$installBackup = Join-Path $BaseDirectory ('.config-backup-' + [guid]::NewGuid().ToString('N') + '.json')
$rollbackBackup = Join-Path $PersistDirectory ('.config-rollback-' + [guid]::NewGuid().ToString('N') + '.json')
$handler = $null
$client = $null
$keepBackup = $false
try {
    if (-not (Test-Path -LiteralPath $urlFile)) { return }
    $url = ([IO.File]::ReadAllText($urlFile)).Trim()
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    $uri = [uri]$url
    if ($uri.Scheme -notin @('http', 'https')) { throw 'Invalid URL scheme.' }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseProxy = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $response = $client.GetAsync($uri).GetAwaiter().GetResult()
    try {
        $response.EnsureSuccessStatusCode() | Out-Null
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        [IO.File]::WriteAllBytes($tempFile, $bytes)
    } finally { $response.Dispose() }
    Push-Location $BaseDirectory
    try {
        & (Join-Path $BaseDirectory 'sing-box.exe') check -c $tempFile
        if ($LASTEXITCODE -ne 0) { throw 'Invalid configuration.' }
    } finally { Pop-Location }
    # Replacements are atomic; replacing either path separates existing Scoop hard links.
    [IO.File]::Copy($tempFile, $installTemp)
    if (Test-Path -LiteralPath $persistConfig) {
        [IO.File]::Replace($tempFile, $persistConfig, $backupFile)
    } else {
        [IO.File]::Move($tempFile, $persistConfig)
    }
    try {
        if (Test-Path -LiteralPath $configFile) {
            [IO.File]::Replace($installTemp, $configFile, $installBackup)
        } else {
            [IO.File]::Move($installTemp, $configFile)
        }
    } catch {
        if (Test-Path -LiteralPath $backupFile) {
            $keepBackup = $true
            [IO.File]::Replace($backupFile, $persistConfig, $rollbackBackup)
            $keepBackup = $false
        }
        throw
    }
    Write-Output 'Configuration downloaded and validated.'
} catch {
    # Exception details may contain a secret subscription URL.
    Write-Warning 'Configuration update failed; the existing configuration will be used.'
} finally {
    if ($client) { $client.Dispose() }
    if ($handler) { $handler.Dispose() }
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $installTemp -Force -ErrorAction SilentlyContinue
    if (-not $keepBackup) { Remove-Item -LiteralPath $backupFile -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $installBackup -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $rollbackBackup -Force -ErrorAction SilentlyContinue
}
