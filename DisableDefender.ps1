<#
.SYNOPSIS
  Disable Microsoft Defender by suspending its service, disabling Tamper Protection (with manual fallback),
  enforcing Local GPO settings for real-time protection and full Defender disablement, then refreshing policies.

.NOTES
  • Test in a VM snapshot.  
  • Must be run from a 64-bit, elevated PowerShell prompt.  
  • Downloads PsSuspend directly from live.sysinternals.com.  
#>

#–– Relaunch in 64-bit if needed ––
if ($env:PROCESSOR_ARCHITEW6432) {
    $sysnative = "$env:WinDir\sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnative) {
        Write-Host "Re-launching in 64-bit PowerShell…" -ForegroundColor Cyan
        & $sysnative -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        Exit
    }
}

#–– Elevation check ––
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "ERROR: Script must be run as Administrator."
    Exit 1
}

$ErrorActionPreference = 'Stop'
function Info  { param($m) Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Pass  { param($m) Write-Host "✔️  $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "⚠️  $m" -ForegroundColor Yellow }

#–– Download PsSuspend ––
$archSuffix = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {'64'} else {''}
$psSuspendPath = "$env:TEMP\pssuspend$archSuffix.exe"
$psSuspendUrl  = "https://live.sysinternals.com/pssuspend$archSuffix.exe"
Info "Downloading PsSuspend ($archSuffix-bit)…"
Invoke-WebRequest -Uri $psSuspendUrl -OutFile $psSuspendPath -UseBasicParsing
Pass "PsSuspend downloaded to $psSuspendPath"

#–– Suspend Defender’s process ––
Info "Suspending MsMpEng.exe…"
try {
    & $psSuspendPath -accepteula MsMpEng.exe | Out-Null
    Pass "MsMpEng.exe suspended."
} catch {
    Warn "Couldn’t suspend MsMpEng.exe: $_"
}

#–– Disable Tamper Protection ––
$tpKey = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features'
Info "Attempting to disable Tamper Protection via registry…"
try {
    # Try taking ownership & writing
    $acl = Get-Acl $tpKey
    $acl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
        "Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl -Path $tpKey -AclObject $acl
    Set-ItemProperty -Path $tpKey -Name TamperProtection -Type DWord -Value 0 -Force
    Pass "Tamper Protection turned off (registry)."
} catch {
    Warn "Registry modification failed: $_"
    Write-Host
    Write-Host "→ Please open Windows Security:" -ForegroundColor Yellow
    Write-Host "   Virus & threat protection → Manage settings → Tamper Protection: Off" -ForegroundColor Yellow
    Read-Host "Once Tamper Protection is off, press Enter to continue"
}

#–– Apply Local GPO settings via registry ––
Info "Disabling real-time protection (Local GPO)…"
$rtKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
if (-not (Test-Path $rtKey)) { New-Item -Path $rtKey -Force | Out-Null }
Set-ItemProperty -Path $rtKey -Name DisableRealtimeMonitoring -Type DWord -Value 1 -Force
Pass "Real-time protection disabled via GPO."

Info "Disabling Microsoft Defender Antivirus (Local GPO)…"
$defKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
if (-not (Test-Path $defKey)) { New-Item -Path $defKey -Force | Out-Null }
Set-ItemProperty -Path $defKey -Name DisableAntiSpyware -Type DWord -Value 1 -Force
Pass "Defender Antivirus disabled via GPO."

#–– Refresh policies ––
Info "Refreshing Group Policy…"
gpupdate /force | Out-Null
Pass "Group Policy refreshed."

#–– Finish ––
Write-Host
Info "All done. A reboot is required to finalize."
if ((Read-Host "Reboot now? (Y/N)") -match '^[Yy]') {
    Info "Rebooting…"
    Restart-Computer -Force
} else {
    Pass "Remember to reboot later."
}
