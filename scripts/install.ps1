# amiga-devbench — one-shot installer for Windows (PowerShell).
#
# Clones the repo, installs the Python host server, pulls the m68k cross-compiler
# Docker image, builds the bridge daemon + examples, and starts the web UI on
# http://localhost:3000.
#
# Invoke as:
#
#   iwr -useb https://raw.githubusercontent.com/geekychris/amiga_mcp/main/scripts/install.ps1 | iex
#
# Requires: PowerShell 5.1+, git, Python 3.10+, Docker Desktop. Run a regular
# (non-admin) PowerShell window — sudo is not needed.
#
# Environment variables (set before invoking):
#   $env:AMIGA_MCP_SRC      install dir       (default: $HOME\.amiga-devbench\src)
#   $env:AMIGA_MCP_REF      git ref           (default: main)
#   $env:AMIGA_MCP_REPO     git remote        (default: https://github.com/geekychris/amiga_mcp.git)
#   $env:AMIGA_MCP_BUILD    1 to build examples via Docker (default: 1)
#   $env:AMIGA_MCP_START    1 to launch the web UI         (default: 1)
#   $env:AMIGA_MCP_OPEN     1 to open browser              (default: 1)

$ErrorActionPreference = 'Stop'

function Get-EnvOr($name, $default) {
    $val = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrEmpty($val)) { return $default } else { return $val }
}

$AppSrc   = Get-EnvOr 'AMIGA_MCP_SRC'   (Join-Path $HOME '.amiga-devbench\src')
$AppRef   = Get-EnvOr 'AMIGA_MCP_REF'   'main'
$AppRepo  = Get-EnvOr 'AMIGA_MCP_REPO'  'https://github.com/geekychris/amiga_mcp.git'
$AppBuild = Get-EnvOr 'AMIGA_MCP_BUILD' '1'
$AppStart = Get-EnvOr 'AMIGA_MCP_START' '1'
$AppOpen  = Get-EnvOr 'AMIGA_MCP_OPEN'  '1'

$RunDir = Join-Path $HOME '.amiga-devbench\run'
$LogDir = Join-Path $HOME '.amiga-devbench\logs'
New-Item -ItemType Directory -Force -Path $RunDir, $LogDir | Out-Null

function Step($msg) { Write-Host "==> " -NoNewline -ForegroundColor Blue; Write-Host $msg -ForegroundColor White }
function OK($msg)   { Write-Host " ✓ " -NoNewline -ForegroundColor Green; Write-Host $msg }
function Warn($msg) { Write-Host " ! " -NoNewline -ForegroundColor Yellow; Write-Host $msg }
function Die($msg)  { Write-Host " ✗ " -NoNewline -ForegroundColor Red; Write-Host $msg; exit 1 }

function Need($bin, $hint) {
    if (-not (Get-Command $bin -ErrorAction SilentlyContinue)) {
        Die "missing '$bin' on PATH — $hint"
    }
}

# --- 1. prereqs ---------------------------------------------------------
Step "Checking prerequisites (Windows)"
Need git    "install from https://git-scm.com/download/win  or: winget install --id Git.Git"

# Pick a python>=3.10
$Py = $null
foreach ($c in 'python','python3','py') {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if (-not $cmd) { continue }
    try {
        $v = & $cmd -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" 2>$null
        $major = [int]($v.Split('.')[0]); $minor = [int]($v.Split('.')[1])
        if (($major -eq 3 -and $minor -ge 10) -or $major -gt 3) {
            $Py = $cmd.Source
            OK "python: $Py ($v)"
            break
        }
    } catch { }
}
if (-not $Py) {
    Die "python>=3.10 not found — install from https://www.python.org/downloads/  or: winget install --id Python.Python.3.12"
}

# Docker is optional (only needed to build examples)
$DockerOk = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    try {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $DockerOk = $true; OK "docker daemon reachable" }
    } catch { }
}
if (-not $DockerOk) {
    Warn "docker daemon not reachable — examples will not build until you start Docker Desktop"
    Warn "install: https://www.docker.com/products/docker-desktop/  (or: winget install --id Docker.DockerDesktop)"
    $AppBuild = '0'
}

# pip available?
try {
    & $Py -m pip --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "pip not available" }
    OK "pip available"
} catch {
    Die "pip not available for $Py — re-install Python with 'Add to PATH' and 'pip' options checked"
}

# --- 2. source ---------------------------------------------------------
Step "Fetching source -> $AppSrc ($AppRef)"
if (Test-Path (Join-Path $AppSrc '.git')) {
    git -C $AppSrc fetch --quiet origin $AppRef
    git -C $AppSrc checkout --quiet $AppRef
    try { git -C $AppSrc pull --quiet --ff-only origin $AppRef } catch { Warn "could not fast-forward — keeping current state" }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AppSrc) | Out-Null
    git clone --quiet --branch $AppRef $AppRepo $AppSrc
}
OK "source ready"

# --- 3. python host server --------------------------------------------
Step "Installing amiga-devbench (Python host)"
$pipLog = Join-Path $LogDir 'pip.log'
$inVenv = $env:VIRTUAL_ENV
$pipFlags = @('install', '--quiet', '-e', (Join-Path $AppSrc 'amiga-devbench'))
if (-not $inVenv) { $pipFlags = @('install', '--quiet', '--user', '-e', (Join-Path $AppSrc 'amiga-devbench')) }
& $Py -m pip @pipFlags *>$pipLog
if ($LASTEXITCODE -ne 0) {
    Get-Content $pipLog | Write-Host
    Die "pip install failed — see $pipLog"
}
OK "amiga-devbench installed"

# --- 4. cross-compiler image + examples (optional) -------------------
if ($AppBuild -eq '1') {
    Step "Pulling m68k cross-compiler image (amigadev/crosstools:m68k-amigaos)"
    docker pull --quiet amigadev/crosstools:m68k-amigaos | Out-Null
    if ($LASTEXITCODE -ne 0) { Warn "image pull failed — retry later: docker pull amigadev/crosstools:m68k-amigaos" }

    Step "Building amiga-bridge + examples (this takes a minute)"
    $buildLog = Join-Path $LogDir 'build.log'
    Push-Location $AppSrc
    try {
        # Use docker run directly; Windows doesn't have make by default.
        $cwd = (Get-Location).Path -replace '\\', '/'
        docker run --rm -v "${cwd}:/work" -w /work amigadev/crosstools:m68k-amigaos make all *> $buildLog
        if ($LASTEXITCODE -eq 0) { OK "build complete" } else { Warn "build failed — see $buildLog" }
    } finally { Pop-Location }
} else {
    Step "Skipping example build (AMIGA_MCP_BUILD=0 or docker unavailable)"
}

if ($AppStart -ne '1') {
    Write-Host ""
    Write-Host "Install complete. To start:"
    Write-Host "  cd $AppSrc"
    Write-Host "  $Py -m amiga_devbench"
    Write-Host ""
    Write-Host "Then open http://localhost:3000 in your browser."
    exit 0
}

# --- 5. launch web UI in background ----------------------------------
Step "Starting amiga-devbench on http://localhost:3000"
$devLog = Join-Path $LogDir 'devbench.log'
$pidFile = Join-Path $RunDir 'devbench.pid'

if (Test-Path $pidFile) {
    try {
        $existingPid = [int](Get-Content $pidFile)
        if (Get-Process -Id $existingPid -ErrorAction SilentlyContinue) {
            Warn "devbench already running (pid $existingPid)"
        }
    } catch { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
}

if (-not (Test-Path $pidFile) -or -not (Get-Process -Id ([int](Get-Content $pidFile -ErrorAction SilentlyContinue)) -ErrorAction SilentlyContinue)) {
    $proc = Start-Process -FilePath $Py -ArgumentList @('-m','amiga_devbench') -WorkingDirectory $AppSrc `
        -RedirectStandardOutput $devLog -RedirectStandardError "$devLog.err" `
        -WindowStyle Hidden -PassThru
    $proc.Id | Out-File -FilePath $pidFile -Encoding ascii
    OK "devbench pid $($proc.Id) — log: $devLog"
}

# --- 6. health probe + summary --------------------------------------
Step "Waiting for web UI"
$up = $false
for ($i = 1; $i -le 30; $i++) {
    try {
        $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 1 -Uri http://localhost:3000/health
        OK "up"; $up = $true; break
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $up) { Warn "not responding after 30s — check $devLog" }

Write-Host ""
Write-Host "amiga-devbench is up." -ForegroundColor White
Write-Host ""
Write-Host "  Web UI    http://localhost:3000"
Write-Host "  MCP       http://localhost:3000/mcp"
Write-Host "  source    $AppSrc"
Write-Host "  logs      $LogDir"
Write-Host "  pids      $RunDir"
Write-Host ""
Write-Host "Stop with:    Stop-Process -Id (Get-Content '$pidFile')"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Install FS-UAE or WinUAE and a Kickstart ROM — see README 'FS-UAE Emulator Setup'."
Write-Host "  2. Edit $AppSrc\devbench.toml and point [emulator] at your fs-uae binary + config."
Write-Host "  3. (Optional) See https://github.com/geekychris/fsuae_remote_patch for the patched"
Write-Host "     fs-uae build with HTTP-driven CPU-level debugging (Linux/macOS only)."

if ($AppOpen -eq '1' -and $up) {
    Start-Process http://localhost:3000 | Out-Null
}
