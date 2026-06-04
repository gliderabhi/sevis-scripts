# =============================================================
# startup-sevis.ps1 - Start the full SEVIS stack on Windows boot
#
# Starts: MySQL → all Java microservices → Angular dev server
# Registered as a Task Scheduler task via register-startup-task.ps1
# =============================================================

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$LogDir      = Join-Path $ProjectRoot "local-logs"
$StartupLog  = Join-Path $LogDir "startup-sevis.log"
$WebDir      = Join-Path $ProjectRoot "ui\sevis-web"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Add-Content -Path $StartupLog -Value $line
    Write-Host $line
}

Log "========== SEVIS startup initiated =========="

# Wait for network (OneDrive sync + internet) before touching anything
Log "Waiting 20s for network and OneDrive to settle..."
Start-Sleep -Seconds 20

# ---------------------------------------------------------------
# Backend services (script_local_windows.ps1 handles MySQL + all JARs)
# ---------------------------------------------------------------
Log "Starting backend services..."
$backendScript = Join-Path $ScriptDir "script_local_windows.ps1"
try {
    & $backendScript 2>&1 | Tee-Object -FilePath $StartupLog -Append
    Log "Backend script completed."
} catch {
    Log "ERROR running backend script: $_"
    exit 1
}

# ---------------------------------------------------------------
# Angular dev server
# ---------------------------------------------------------------
Log "Starting Angular dev server..."
$ngLog    = Join-Path $LogDir "sevis-web.log"
$ngLogErr = Join-Path $LogDir "sevis-web.err"

# Clear old logs so previous session output doesn't linger
Clear-Content $ngLog    -ErrorAction SilentlyContinue
Clear-Content $ngLogErr -ErrorAction SilentlyContinue

$proc = Start-Process `
    -FilePath "$WebDir\node_modules\.bin\ng.cmd" `
    -ArgumentList "serve", "--host", "0.0.0.0" `
    -WorkingDirectory $WebDir `
    -RedirectStandardOutput $ngLog `
    -RedirectStandardError  $ngLogErr `
    -PassThru `
    -WindowStyle Hidden

Log "Angular started (PID $($proc.Id)) -> http://localhost:4200"
Log "========== SEVIS startup complete =========="
