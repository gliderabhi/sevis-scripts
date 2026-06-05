# =============================================================
# script_local_windows.ps1 - Build and run SEVIS services locally on Windows
#
# Behaviour:
#   - First run  : builds everything, starts all services in order
#   - Re-run     : rebuilds only services whose source changed since last
#                  JAR build, then restarts only those services
#   - sevis-common changed : republishes it and rebuilds all dependent services
#
# Usage:
#   .\sevis-scripts\script_local_windows.ps1         # smart build + start
#   .\sevis-scripts\script_local_windows.ps1 stop    # stop all services
# =============================================================
param([string]$Action = "")

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$SevisRoot   = Join-Path $ProjectRoot "sevis"
$CommonRoot  = Join-Path $ProjectRoot "common"
$PhotosRoot  = "D:\projects\photos"
$LogDir      = Join-Path $ProjectRoot "local-logs"
$PidDir      = Join-Path $ProjectRoot "local-pids"

$MysqlBin = "C:\Program Files\MySQL\MySQL Server 8.4\bin"
$MysqlCnf = "C:\ProgramData\MySQL\MySQL Server 8.4\my.ini"

$JavaHome = "C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot"
if ((-not (Test-Path $JavaHome)) -and $env:JAVA_HOME) { $JavaHome = $env:JAVA_HOME }
$Java = Join-Path $JavaHome "bin\java.exe"

# Ordered map: determines build AND startup order
$ServiceDirs = [ordered]@{
    "eureka-server"     = Join-Path $CommonRoot "eureka-server"
    "gateway"           = Join-Path $CommonRoot "gateway"
    "user-service"      = Join-Path $CommonRoot "user-service"
    "inventory-service" = Join-Path $SevisRoot "inventory-service"
    "billing-service"   = Join-Path $SevisRoot "billing-service"
    "orders-service"    = Join-Path $SevisRoot "orders-service"
    "photo-service"     = Join-Path $PhotosRoot "photo-service"
}

# Startup order (eureka first, gateway last)
$StartOrder = @("eureka-server", "user-service", "inventory-service", "billing-service", "orders-service", "photo-service", "gateway")

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $PidDir | Out-Null

# ---------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------

# Returns the LastWriteTime of the newest source/config file under $dir
function Get-NewestSourceTime {
    param([string]$dir)
    $extensions = @('.java', '.kt', '.gradle', '.kts', '.xml', '.yml', '.yaml', '.properties')
    $newest = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { $extensions -contains $_.Extension } |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if ($newest) { return $newest.LastWriteTime }
    return [DateTime]::MinValue
}

# Returns LastWriteTime of the boot JAR, or MinValue if none exists yet
function Get-JarTime {
    param([string]$dir)
    $jar = Get-ChildItem -Path "$dir\build\libs\*.jar" -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike "*-plain.*" } |
           Select-Object -First 1
    if ($jar) { return $jar.LastWriteTime }
    return [DateTime]::MinValue
}

# Returns $true if the service's PID file exists and the process is alive
function Test-SvcRunning {
    param([string]$svc)
    $pidFile = Join-Path $PidDir "$svc.pid"
    if (-not (Test-Path $pidFile)) { return $false }
    $savedPid = [int](Get-Content $pidFile -Raw).Trim()
    try {
        $proc = Get-Process -Id $savedPid -ErrorAction Stop
        return (-not $proc.HasExited)
    } catch {
        return $false
    }
}

# Starts a service as a background process; records PID
function Start-Svc {
    param([string]$svc)
    $dir     = $ServiceDirs[$svc]
    $libsDir = Join-Path $dir "build\libs"
    $jar     = Get-ChildItem -Path "$libsDir\*.jar" -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike "*-plain.*" } |
               Select-Object -First 1
    $logFile = Join-Path $LogDir "$svc.log"
    $pidFile = Join-Path $PidDir "$svc.pid"

    if (-not $jar) {
        Write-Host "  FAIL  No JAR found for $svc in $libsDir"
        return
    }

    $startArgs = @{
        FilePath               = $Java
        ArgumentList           = "-Xmx256m", "-Xms64m", "-jar", $jar.FullName
        RedirectStandardOutput = $logFile
        RedirectStandardError  = "$logFile.err"
        PassThru               = $true
        WindowStyle            = "Hidden"
    }
    $proc = Start-Process @startArgs
    $proc.Id | Set-Content $pidFile
    Write-Host "  OK  $svc  (PID $($proc.Id))  ->  $logFile"
}

# Stops a running service (if alive) then starts the new JAR
function Restart-Svc {
    param([string]$svc)
    $pidFile = Join-Path $PidDir "$svc.pid"
    if (Test-Path $pidFile) {
        $savedPid = [int](Get-Content $pidFile -Raw).Trim()
        try {
            Stop-Process -Id $savedPid -Force -ErrorAction Stop
            Write-Host "  Stopped $svc (PID $savedPid)"
        } catch {
            Write-Host "  $svc was already stopped"
        }
        Remove-Item $pidFile -Force
        Start-Sleep -Seconds 2
    }
    Start-Svc $svc
}

# ---------------------------------------------------------------
# STOP
# ---------------------------------------------------------------
function Stop-AllServices {
    Write-Host "Stopping all local SEVIS services..."
    foreach ($svc in $ServiceDirs.Keys) {
        $pidFile = Join-Path $PidDir "$svc.pid"
        if (Test-Path $pidFile) {
            $savedPid = [int](Get-Content $pidFile -Raw).Trim()
            try {
                Stop-Process -Id $savedPid -Force -ErrorAction Stop
                Write-Host "  Stopped $svc (PID $savedPid)"
            } catch {
                Write-Host "  $svc already stopped"
            }
            Remove-Item $pidFile -Force
        }
    }
    Write-Host "Done."
}

if ($Action -eq "stop") {
    Stop-AllServices
    exit 0
}

# ---------------------------------------------------------------
# HEADER
# ---------------------------------------------------------------
Write-Host ""
Write-Host "========================================================="
Write-Host "       SEVIS - Local Development Stack (Windows)"
Write-Host "========================================================="
Write-Host ""

# ---------------------------------------------------------------
# MYSQL
# ---------------------------------------------------------------
Write-Host "[mysql] Checking MySQL..."
$mysqlExe  = Join-Path $MysqlBin "mysql.exe"
$mysqldExe = Join-Path $MysqlBin "mysqld.exe"

$mysqlUp = $false
try {
    & $mysqlExe -u root --connect-timeout=2 -e "SELECT 1;" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $mysqlUp = $true }
} catch { }

if ($mysqlUp) {
    Write-Host "  OK  MySQL already running"
} else {
    Write-Host "  Starting MySQL..."
    $mysqldLog = Join-Path $env:TEMP "mysqld.log"
    $startArgs = @{
        FilePath               = $mysqldExe
        ArgumentList           = "--defaults-file=`"$MysqlCnf`"", "--console"
        PassThru               = $true
        WindowStyle            = "Hidden"
        RedirectStandardOutput = $mysqldLog
    }
    $mysqldProc = Start-Process @startArgs
    $mysqldProc.Id | Set-Content (Join-Path $env:TEMP "mysqld.pid")

    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        try {
            & $mysqlExe -u root --connect-timeout=2 -e "SELECT 1;" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        } catch { }
    }

    if ($ready) {
        Write-Host "  OK  MySQL started (PID $($mysqldProc.Id))"
    } else {
        Write-Host "  FAIL  MySQL did not start - check $mysqldLog"
        exit 1
    }
}

$env:JAVA_HOME = $JavaHome

# ---------------------------------------------------------------
# DETECT WHAT NEEDS REBUILDING
# ---------------------------------------------------------------
Write-Host ""
Write-Host "Checking for changes..."

$commonDir     = Join-Path $SevisRoot "sevis-common"
$commonNewest  = Get-NewestSourceTime $commonDir
$rebuildCommon = $false
$toBuild       = [System.Collections.Generic.List[string]]::new()

foreach ($svc in $ServiceDirs.Keys) {
    $jarTime  = Get-JarTime $ServiceDirs[$svc]
    $svcNewest = Get-NewestSourceTime $ServiceDirs[$svc]

    if ($jarTime -eq [DateTime]::MinValue) {
        Write-Host "  $svc  -> no JAR, will build"
        $toBuild.Add($svc) | Out-Null
    } elseif ($commonNewest -gt $jarTime) {
        Write-Host "  $svc  -> sevis-common changed, will rebuild"
        $rebuildCommon = $true
        $toBuild.Add($svc) | Out-Null
    } elseif ($svcNewest -gt $jarTime) {
        Write-Host "  $svc  -> source changed, will rebuild"
        $toBuild.Add($svc) | Out-Null
    } else {
        Write-Host "  $svc  -> up to date, skipping build"
    }
}

if ($toBuild.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing to build."
}

# ---------------------------------------------------------------
# BUILD sevis-common (only if a service depends on it changing)
# ---------------------------------------------------------------
if ($rebuildCommon -or ($toBuild.Count -gt 0)) {
    Write-Host ""
    Write-Host "Publishing sevis-common to Maven Local..."
    Push-Location $commonDir
    .\gradlew.bat publishToMavenLocal --no-daemon -q
    $rc = $LASTEXITCODE
    Pop-Location
    if ($rc -ne 0) {
        Write-Host "  FAIL  sevis-common build failed"
        exit 1
    }
    Write-Host "  OK  sevis-common published"
}

# ---------------------------------------------------------------
# BUILD changed services
# ---------------------------------------------------------------
if ($toBuild.Count -gt 0) {
    Write-Host ""
    Write-Host "Building $($toBuild.Count) service(s)..."
    foreach ($svc in $toBuild) {
        Write-Host "  Building $svc..."
        Push-Location $ServiceDirs[$svc]
        .\gradlew.bat bootJar --no-daemon -q
        $rc = $LASTEXITCODE
        Pop-Location
        if ($rc -ne 0) {
            Write-Host "  FAIL  Build failed for $svc - aborting."
            exit 1
        }
        Write-Host "  OK  $svc built"
    }
}

# ---------------------------------------------------------------
# START / RESTART services
# ---------------------------------------------------------------
Write-Host ""
Write-Host "Starting services..."

$eurekaWasStarted = $false

foreach ($svc in $StartOrder) {
    $running  = Test-SvcRunning $svc
    $wasBuilt = $toBuild.Contains($svc)

    if (-not $running) {
        # Not running at all - start it
        Write-Host "  Starting $svc..."
        Start-Svc $svc

        if ($svc -eq "eureka-server") {
            Write-Host "     Waiting 20s for Eureka to come up..."
            Start-Sleep -Seconds 20
            $eurekaWasStarted = $true
        }
    } elseif ($wasBuilt) {
        # Running but rebuilt - restart it
        Write-Host "  Restarting $svc (source changed)..."
        Restart-Svc $svc

        if ($svc -eq "eureka-server") {
            Write-Host "     Waiting 20s for Eureka to come back up..."
            Start-Sleep -Seconds 20
            $eurekaWasStarted = $true
        }
    } else {
        Write-Host "  $svc  -> already running, no changes"
    }
}

# Wait for service registration only when something actually changed
if ($toBuild.Count -gt 0 -and (-not $eurekaWasStarted)) {
    Write-Host "     Waiting 10s for changed services to register..."
    Start-Sleep -Seconds 10
} elseif ($eurekaWasStarted) {
    Write-Host "     Waiting 15s for services to register with Eureka..."
    Start-Sleep -Seconds 15
}

# ---------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------
Write-Host ""
Write-Host "========================================================="
if ($toBuild.Count -eq 0) {
    Write-Host "  No changes detected - all services already up to date"
} else {
    Write-Host "  Rebuilt and restarted: $($toBuild -join ', ')"
}
Write-Host "---------------------------------------------------------"
Write-Host "  Eureka   ->  http://localhost:8761"
Write-Host "  Gateway  ->  http://localhost:8080"
Write-Host "  Angular  ->  http://localhost:4200  (run ng serve separately)"
Write-Host "---------------------------------------------------------"
Write-Host "  Logs     ->  $LogDir"
Write-Host "  Stop     ->  .\sevis-scripts\script_local_windows.ps1 stop"
Write-Host "========================================================="
Write-Host ""
