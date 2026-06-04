# =============================================================
# register-startup-task.ps1 - Register SEVIS auto-start in Task Scheduler
#
# Run this ONCE as Administrator to install the startup task.
# The task fires at user logon and runs startup-sevis.ps1.
# =============================================================

$TaskName   = "SevisLocalStack"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartupScript = Join-Path $ScriptDir "startup-sevis.ps1"
$CurrentUser   = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Remove any existing task with the same name
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$StartupScript`""

# Trigger: at logon of the current user
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 1 `
    -RestartInterval (New-TimeSpan -Minutes 2) `
    -StartWhenAvailable `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

$principal = New-ScheduledTaskPrincipal `
    -UserId $CurrentUser `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action   $action `
    -Trigger  $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Starts the full SEVIS local dev stack (MySQL, microservices, Angular) at user logon" `
    -Force | Out-Null

Write-Host ""
Write-Host "Task '$TaskName' registered successfully."
Write-Host "  Triggers : at logon of $CurrentUser"
Write-Host "  Script   : $StartupScript"
Write-Host ""
Write-Host "To remove the task later:"
Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host ""
