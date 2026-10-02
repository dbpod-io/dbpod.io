# dbpod installer (Windows) - https://dbpod.io
#
# CLI only:
#   irm https://dbpod.io/install.ps1 | iex
#
# CLI + database engine(s) in one shot (irm | iex cannot take parameters,
# so the engine form uses the scriptblock invocation):
#   & ([scriptblock]::Create((irm https://dbpod.io/install.ps1))) -Engine mysql@8.0
#   ... -Engine mysql@8.0 -Engine postgres@17
#
# Env-var equivalents work with both forms:
#   $env:DBPOD_VERSION = 'v0.1.0'; irm https://dbpod.io/install.ps1 | iex
#   $env:DBPOD_ENGINES = 'mysql@8.0 postgres@17'
#
# Downloads the dbpod binary from GitHub Releases, verifies it against the
# release checksums, and installs it into ~\.local\bin.

[CmdletBinding()]
param(
  [string]$Version = '',
  [string[]]$Engine = @(),
  [string]$InstallDir = ''
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Repo = 'dbpod-io/dbpod'
$Releases = "https://github.com/$Repo/releases"

function log($msg) { Write-Host "info: $msg" }
function fail($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

# download with retries; transient network errors get 5 attempts with
# backoff, 404s fail fast. Honors HTTPS_PROXY like curl does (PS 5.1's
# Invoke-WebRequest ignores the env var on its own).
function Fetch($url, $out) {
  $proxy = $env:HTTPS_PROXY
  if (-not $proxy) { $proxy = $env:https_proxy }
  $waits = @(0, 2, 4, 8, 16)
  for ($i = 1; $i -le 5; $i++) {
    try {
      if ($proxy) {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -Proxy $proxy -ErrorAction Stop
      } else {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -ErrorAction Stop
      }
      return $true
    } catch {
      $sc = $_.Exception.Response.StatusCode.value__
      if ($sc -eq 404 -or $i -eq 5) { return $false }
      log "download attempt $i failed, retrying in $($waits[$i])s ..."
      Start-Sleep -Seconds $waits[$i]
    }
  }
}

# --- options (env-var fallbacks for the irm | iex form) --------------------
if (-not $Version) { $Version = $env:DBPOD_VERSION }
if (-not $Version) { $Version = 'latest' }
if ($Engine.Count -eq 0 -and $env:DBPOD_ENGINES) {
  $Engine = @($env:DBPOD_ENGINES -split '[,\s]+' | Where-Object { $_ })
}
if (-not $InstallDir) {
  if ($env:DBPOD_INSTALL_DIR) { $InstallDir = $env:DBPOD_INSTALL_DIR }
  else { $InstallDir = Join-Path $HOME '.local\bin' }
}
foreach ($e in $Engine) {
  if ($e -notmatch '@') {
    fail "engine ref must look like <engine>@<version> (e.g. mysql@8.0), got: $e"
  }
}

# --- detect platform -------------------------------------------------------
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$asset = "dbpod-windows-$arch.zip"

if ($Version -eq 'latest') { $baseUrl = "$Releases/latest/download" }
else { $baseUrl = "$Releases/download/$Version" }

# --- download --------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dbpod-install-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
  log "downloading $asset ..."
  $zipPath = Join-Path $tmp $asset
  if (-not (Fetch "$baseUrl/$asset" $zipPath)) {
    fail "download failed: $baseUrl/$asset"
  }

  # --- verify checksum -----------------------------------------------------
  if (Fetch "$baseUrl/checksums.txt" (Join-Path $tmp 'checksums.txt')) {
    $line = Get-Content (Join-Path $tmp 'checksums.txt') |
      Where-Object { $_ -match '^\s*([0-9a-fA-F]{64})\s+(\S+)\s*$' -and $Matches[2] -eq $asset } |
      Select-Object -First 1
    if (-not $line) { fail "checksum for $asset not found in checksums.txt" }
    $want = ($line -split '\s+')[0].ToLower()
    # .NET directly - Get-FileHash needs module autoloading, which breaks in
    # environments with a polluted PSModulePath
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $got = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($zipPath))).Replace('-', '').ToLower()
    } finally {
      $sha.Dispose()
    }
    if ($got -ne $want) { fail "checksum mismatch for ${asset}: got $got, want $want" }
    log "checksum ok ($got)"
  } else {
    log 'checksums.txt unavailable; skipping checksum verification'
  }

  # --- install -------------------------------------------------------------
  # .NET extraction - Expand-Archive needs module autoloading, which breaks
  # in environments with a polluted PSModulePath
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tmp)
  $exe = Join-Path $tmp 'dbpod.exe'
  if (-not (Test-Path $exe)) {
    throw 'archive did not contain a dbpod.exe binary - asset layout mismatch?'
  }
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $dbpod = Join-Path $InstallDir 'dbpod.exe'
  try {
    Copy-Item -Force -Path $exe -Destination $dbpod
  } catch {
    fail "cannot write $dbpod - is a running dbpod.exe locking the file?"
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# --- install requested engines ---------------------------------------------
foreach ($e in $Engine) {
  log "installing engine $e ..."
  & (Join-Path $InstallDir 'dbpod.exe') engine install $e
  if ($LASTEXITCODE -ne 0) { fail "engine install failed: $e" }
}

if (($env:Path -split ';') -notcontains $InstallDir) {
  log "$InstallDir is not in your PATH"
  Write-Host "add it for this session:  `$env:Path = `"$InstallDir;`$env:Path`""
  Write-Host "add it permanently:  [Environment]::SetEnvironmentVariable('Path', `"$InstallDir;`" + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')"
}

Write-Host ''
Write-Host "dbpod installed -> $(Join-Path $InstallDir 'dbpod.exe')"
& (Join-Path $InstallDir 'dbpod.exe') version

if ($Engine.Count -gt 0) {
  Write-Host "get started:  dbpod run --name dev --engine $($Engine[0])"
} else {
  Write-Host 'get started:  dbpod engine install mysql@8.0'
}
