<#
.SYNOPSIS
  Fully automates the download and installation of FLARE-VM (no GUI).

.DESCRIPTION
  1. Verifies running as Administrator.
  2. Pauses Windows Update service.
  3. Disables Defender real-time and tamper protection.
  4. Sets unrestricted execution policy for CurrentUser.
  5. Downloads Mandiant's install.ps1 to %TEMP%.
  6. Unblocks and runs it with -noGui.
  7. Logs output to Install-FLAREVM.log in the same folder.
  8. Re-enables Defender protections.
  9. Restarts PC when done.

.NOTES
  Run inside a clean snapshot. Requires Internet (NAT/Bridged).
#>

# 1) Ensure running as Admin
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Script must be run as Administrator. Exiting."
    Exit 1
}

$ErrorActionPreference = 'Stop'
$logFile = Join-Path $PSScriptRoot 'Install-FLAREVM.log'

Function Log {
    Param ($msg)
    $timestamp = (Get-Date).ToString('s')
    "$timestamp  $msg" | Tee-Object -FilePath $logFile -Append
}

Log "=== Starting FLARE-VM deployment ==="

# 2) Stop Windows Update (optional but prevents auto-reboots)
Try {
    Log "Stopping Windows Update service..."
    Stop-Service wuauserv -ErrorAction SilentlyContinue
} Catch { Log "Warning: Could not stop wuauserv: $_" }

# 3) Disable Defender real-time & Tamper Protection
Log "Disabling Windows Defender real-time monitoring..."
Set-MpPreference -DisableRealtimeMonitoring $true

Log "Disabling Tamper Protection via registry..."
# Note: Some systems ignore this if Tamper Protection enforced by MDM
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features'
If (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name 'TamperProtection' -Value 0 -Force

# 4) Set Execution Policy
Log "Setting ExecutionPolicy to Unrestricted for CurrentUser..."
Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force

# 5) Download installer script
$installerUrl = 'https://raw.githubusercontent.com/mandiant/flare-vm/master/install.ps1'
$installerPath = Join-Path $env:TEMP 'flare-install.ps1'
Log "Downloading FLARE-VM installer to $installerPath..."
Invoke-WebRequest -Uri $installerUrl -UseBasicParsing -OutFile $installerPath

# 6) Unblock & run installer
Log "Unblocking installer and launching with -noGui..."
Unblock-File -Path $installerPath

# Run installer, capture output
Try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installerPath -noGui 2>&1 |
      Tee-Object -FilePath $logFile
} Catch {
    Log "ERROR during FLARE-VM install: $_"
    Throw
}

# 7) Re-enable protections
Log "Re-enabling Windows Defender real-time monitoring..."
Set-MpPreference -DisableRealtimeMonitoring $false

Log "Re-enabling Tamper Protection (user may need to toggle back in UI)..."
Set-ItemProperty -Path $regPath -Name 'TamperProtection' -Value 1 -Force

# 8) Restart prompt
Log "FLARE-VM install complete. Prompting for restart..."
Write-Host
Write-Host "=== FLARE-VM installed successfully! ===" -ForegroundColor Green
Write-Host "Log file: $logFile"
If ($Host.UI.RawUI.WindowTitle) { }  # ensure coloring works
$resp = Read-Host "Reboot now? (Y/N)"
If ($resp -match '^[Yy]') {
    Log "User opted to reboot. Restarting..."
    Restart-Computer
} Else {
    Log "User deferred reboot."
    Write-Host "Please reboot manually to finalize installation."
}

Log "=== End of script ==="
