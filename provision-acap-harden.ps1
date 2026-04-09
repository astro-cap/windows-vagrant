#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 VM Hardening Script for KVM/QEMU environments.
    Idempotent — safe to run multiple times.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# --- FIREWALL ---
Write-Host "[*] Configuring Windows Firewall"
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow -LogBlocked True
$smbBlock = Get-NetFirewallRule -DisplayName "HardenSMB-BlockPublic" -ErrorAction SilentlyContinue
if (-not $smbBlock) {
    New-NetFirewallRule -DisplayName "HardenSMB-BlockPublic" -Direction Inbound -Protocol TCP -LocalPort 445 -Profile Public -Action Block | Out-Null
}

# --- DISABLE UNNECESSARY SERVICES ---
Write-Host "[*] Disabling unnecessary services"
$servicesToDisable = @(
    'DiagTrack', 'dmwappushservice', 'SysMain', 'WSearch', 'Fax',
    'lfsvc', 'MapsBroker', 'RetailDemo', 'WbioSrvc',
    'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'wisvc'
)
foreach ($svc in $servicesToDisable) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

# --- SECURITY HARDENING ---
Write-Host "[*] Applying security hardening"
# UAC
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin" 2
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" 1
# LSA Protection
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RunAsPPL" 1
# Disable SMBv1
Disable-WindowsOptionalFeature -Online -FeatureName 'smb1protocol' -NoRestart -ErrorAction SilentlyContinue
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
# Disable LLMNR and NetBIOS
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters" "NetbiosOptions" 2
# PowerShell logging
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" "EnableScriptBlockLogging" 1
# Defender PUA protection
Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue

# --- TELEMETRY / PRIVACY ---
Write-Host "[*] Reducing telemetry"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowDiagnosticData" 0
Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" "Disabled" 1
Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1

# --- VM PERFORMANCE ---
Write-Host "[*] Optimizing for VM"
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2
Set-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0
Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String"
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
powercfg -h off 2>$null
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0

# --- KVM/QEMU TWEAKS ---
Write-Host "[*] Applying KVM/QEMU tweaks"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" "SearchOrderConfig" 0
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "IoPageLockLimit" 983040
Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" "AutoReboot" 0
Set-RegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" "MaintenanceDisabled" 1

# --- DISABLE WINDOWS DEFENDER ---
Write-Host "[*] Disabling Windows Defender"
# Use reg.exe to avoid Defender blocking the PowerShell script
cmd /c 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableAntiSpyware /t REG_DWORD /d 1 /f' 2>$null
cmd /c 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 1 /f' 2>$null
cmd /c 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableBehaviorMonitoring /t REG_DWORD /d 1 /f' 2>$null
cmd /c 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableOnAccessProtection /t REG_DWORD /d 1 /f' 2>$null
cmd /c 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v DisableScanOnRealtimeEnable /t REG_DWORD /d 1 /f' 2>$null

# --- DISABLE SYSTEM RESTORE ---
Write-Host "[*] Disabling System Restore"
Disable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
vssadmin delete shadows /all /quiet 2>$null
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" "DisableSR" 1
Set-Service -Name 'srservice' -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name 'srservice' -Force -ErrorAction SilentlyContinue

# --- BUSINESS IDENTITY ---
Write-Host "[*] Setting business identity"
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'srvcomment' -Value 'Astro Capital - Workstation' -Force

Write-Host "[+] Hardening complete." -ForegroundColor Green
