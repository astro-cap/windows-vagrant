#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Low-latency tuning for Astro Capital trading workstations (KVM/QEMU).
    TCP/IP, timer, CPU scheduling, memory, power, NIC optimization.
    Idempotent — safe to run multiple times.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# --- TCP/IP: Disable Nagle on all interfaces ---
Write-Host "[*] TCP/IP tuning"
$ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
foreach ($iface in $ifaces) {
    Set-ItemProperty -Path $iface.PSPath -Name "TcpNoDelay" -Value 1 -Type DWord -Force -EA SilentlyContinue
    Set-ItemProperty -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -EA SilentlyContinue
}
netsh int tcp set global autotuninglevel=disabled 2>$null
netsh int tcp set global rss=enabled 2>$null
netsh int tcp set global rsc=disabled 2>$null
$mmPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-ItemProperty -Path $mmPath -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
netsh int ipv4 set dynamicport tcp start=1025 num=64510 2>$null
netsh int ipv4 set dynamicport udp start=1025 num=64510 2>$null

# --- Timer: TSC clock, disable dynamic tick ---
Write-Host "[*] Timer resolution"
bcdedit /deletevalue useplatformclock 2>$null
bcdedit /set useplatformtick yes 2>$null
bcdedit /set disabledynamictick yes 2>$null
bcdedit /set tscsyncpolicy Enhanced 2>$null
$timerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
if (-not (Test-Path $timerPath)) { New-Item -Path $timerPath -Force | Out-Null }
Set-ItemProperty -Path $timerPath -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $timerPath -Name "DisableDynamicTick" -Value 1 -Type DWord -Force

# --- CPU scheduling: short quanta, no foreground boost ---
Write-Host "[*] CPU scheduling"
$schedPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
Set-ItemProperty -Path $schedPath -Name "Win32PrioritySeparation" -Value 0x26 -Type DWord -Force
Set-ItemProperty -Path $schedPath -Name "IRQ8Priority" -Value 1 -Type DWord -Force

# --- Memory: keep kernel in RAM ---
Write-Host "[*] Memory tuning"
$memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $memPath -Name "LargeSystemCache" -Value 0 -Type DWord -Force

# --- Power: Ultimate Performance, no throttling, no C-states, no parking ---
Write-Host "[*] Power management"
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
if ($LASTEXITCODE -ne 0) { powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c }
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR IDLEDISABLE 1 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0 2>$null
powercfg /setactive SCHEME_CURRENT 2>$null
powercfg /hibernate off 2>$null

# --- NIC: disable interrupt moderation, EEE, LSO ---
Write-Host "[*] NIC tuning"
$nics = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
foreach ($nic in $nics) {
    $n = $nic.Name
    Set-NetAdapterAdvancedProperty -Name $n -DisplayName "Interrupt Moderation" -DisplayValue "Disabled" -EA SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $n -DisplayName "Receive Buffers" -DisplayValue "1024" -EA SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $n -DisplayName "Transmit Buffers" -DisplayValue "512" -EA SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $n -DisplayName "Energy Efficient Ethernet" -DisplayValue "Disabled" -EA SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $n -DisplayName "Large Send Offload V2 (IPv4)" -DisplayValue "Disabled" -EA SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $n -DisplayName "Flow Control" -DisplayValue "Disabled" -EA SilentlyContinue
    Set-NetAdapterRss -Name $n -Enabled $true -EA SilentlyContinue
}

# --- Windows Update: no auto-reboot ---
Write-Host "[*] Windows Update policy"
$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $wuPath -Name "AUOptions" -Value 2 -Type DWord -Force

Write-Host "[+] Trading tuning complete. Reboot required for BCD changes." -ForegroundColor Green
