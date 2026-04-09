#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 debloat for Astro Capital trading VMs.
    Removes bloatware, disables widgets/Teams/search, simplifies taskbar.
    Inspired by christitustech/winutil. Idempotent.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# --- REMOVE APPX BLOATWARE ---
Write-Host "[*] Removing bloatware apps"
$bloatApps = @(
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingFinance'
    'Microsoft.BingSports'
    'Microsoft.GamingApp'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.MixedReality.Portal'
    'Microsoft.MSPaint'
    'Microsoft.Office.OneNote'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.SkypeApp'
    'Microsoft.StorePurchaseApp'
    'Microsoft.Todos'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCamera'
    'Microsoft.WindowsCommunicationsApps'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftCorporationII.QuickAssist'
    'MicrosoftTeams'
    'Microsoft.549981C3F5F10'
    'Clipchamp.Clipchamp'
    'Disney.37853FC22B2CE'
    'SpotifyAB.SpotifyMusic'
    'king.com.CandyCrushSaga'
    'king.com.CandyCrushSodaSaga'
    'BytedancePte.Ltd.TikTok'
    'Microsoft.OutlookForWindows'
    'Microsoft.WindowsStore'
    'Microsoft.MicrosoftEdge.Stable'
)

foreach ($app in $bloatApps) {
    Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue |
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$app*" } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# --- TASKBAR: Left-aligned, no widgets, no search, no chat ---
Write-Host "[*] Configuring taskbar (left-aligned, minimal)"
$taskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# Left-align taskbar (0 = left, 1 = center)
Set-RegValue $taskbarPath "TaskbarAl" 0
# Hide Task View button
Set-RegValue $taskbarPath "ShowTaskViewButton" 0
# Hide Widgets
Set-RegValue $taskbarPath "TaskbarDa" 0
# Hide Chat/Teams
Set-RegValue $taskbarPath "TaskbarMn" 0
# Hide Copilot
Set-RegValue $taskbarPath "ShowCopilotButton" 0

# Disable search bar (0=hidden, 1=icon, 2=bar)
$searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
Set-RegValue $searchPath "SearchboxTaskbarMode" 0

# --- START MENU: Simple, no recommendations, no recent ---
Write-Host "[*] Simplifying Start Menu"
$startPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-RegValue $startPath "Start_Layout" 1
# Disable recent files in Start
Set-RegValue $startPath "Start_TrackDocs" 0
# Disable recently installed apps
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" "ShowRecentList" 0
# Disable recommendations
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecommendedSection" 1

# --- DISABLE WIDGETS SERVICE ---
Write-Host "[*] Disabling Widgets"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
$widgetSvc = Get-Service -Name "WpnUserService*" -ErrorAction SilentlyContinue
# Disable Widgets process
Get-Process -Name "Widgets" -ErrorAction SilentlyContinue | Stop-Process -Force

# --- DISABLE TEAMS AUTO-START ---
Write-Host "[*] Disabling Teams auto-start"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" "ChatIcon" 3

# --- DISABLE CORTANA ---
Write-Host "[*] Disabling Cortana"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0

# --- DISABLE ONEDRIVE ---
Write-Host "[*] Disabling OneDrive"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1

# --- DISABLE EDGE FIRST-RUN ---
Write-Host "[*] Disabling Edge first-run experience"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "HideFirstRunExperience" 1

# --- DISABLE CONSUMER FEATURES ---
Write-Host "[*] Disabling consumer features and suggestions"
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding" 1
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" 0
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0

# --- RESTART EXPLORER ---
Write-Host "[*] Restarting Explorer to apply changes"
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process explorer

Write-Host "[+] Debloat complete." -ForegroundColor Green
exit 0
