param()

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "`n[!] Run this script from an elevated PowerShell window." -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

$script:LoggingEnabled = $true
$script:LogFile = $null

function Initialize-Logging {
    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Koolbox.log'),
        (Join-Path $env:LOCALAPPDATA 'WilkoKoolbox\Koolbox.log'),
        (Join-Path $env:TEMP 'Koolbox.log')
    )

    foreach ($candidate in $candidates) {
        try {
            $directory = Split-Path -Path $candidate -Parent
            if (-not (Test-Path -LiteralPath $directory)) {
                New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            Add-Content -LiteralPath $candidate -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Logging started" -Encoding UTF8 -ErrorAction Stop
            $script:LogFile = $candidate
            return
        } catch {
            continue
        }
    }

    $script:LoggingEnabled = $false
    Write-Warning 'Koolbox could not create a log file. Tasks will continue without logging.'
}

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    if (-not $script:LoggingEnabled -or [string]::IsNullOrWhiteSpace($script:LogFile)) { return }

    try {
        $entry = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:LogFile -Value $entry -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging must never cause an install or system task to fail.
        $script:LoggingEnabled = $false
        Write-Warning ("Logging was disabled because '{0}' could not be written: {1}" -f $script:LogFile, $_.Exception.Message)
    }
}

function Write-TaskError {
    param([string]$Task, [System.Management.Automation.ErrorRecord]$ErrorRecord)
    Write-Host "     [!] ${Task} failed: $($ErrorRecord.Exception.Message)" -ForegroundColor Red
    Write-Log "ERROR ${Task}: $($ErrorRecord.Exception.Message)"
}

function Set-RegDword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

function Invoke-Winget {
    param([Parameter(Mandatory)][string]$Id, [switch]$Uninstall)

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Host '     [!] winget is not available. Install/update App Installer from Microsoft Store.' -ForegroundColor Red
        Write-Log "WINGET UNAVAILABLE: $Id"
        return $false
    }

    $verb = if ($Uninstall) { 'uninstall' } else { 'install' }
    Write-Host "     -> $verb $Id ..." -ForegroundColor DarkGray
    $arguments = @($verb, '--id', $Id, '-e', '--accept-source-agreements')
    if ($Uninstall) {
        $arguments += '--silent'
    } else {
        $arguments += '--accept-package-agreements'
    }

    & winget.exe @arguments
    if ($LASTEXITCODE -eq 0) {
        Write-Host "     [OK] $Id" -ForegroundColor Green
        Write-Log "$verb SUCCESS: $Id"
        return $true
    }

    Write-Host "     [!] $Id returned exit code $LASTEXITCODE" -ForegroundColor Yellow
    Write-Log "$verb FAILED: $Id (exit $LASTEXITCODE)"
    return $false
}

function Test-GHelper { return $null -ne (Get-Process -Name 'GHelper' -ErrorAction SilentlyContinue) }

function Get-ActivePlanName {
    $line = (powercfg /getactivescheme | Out-String).Trim()
    if ($line -match '\(([^)]+)\)\s*$') { return $Matches[1].Trim() }
    return $line
}

function Find-InstalledApp {
    param([Parameter(Mandatory)][string]$DisplayName)
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    return Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName.StartsWith($DisplayName, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
}

function Show-Menu {
    Clear-Host
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '                  WILKO KOOLBOX v3.5                     ' -ForegroundColor White
    Write-Host '        All-In-One Dev & Gaming Environment Builder      ' -ForegroundColor DarkGray
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host ' [1]  System : Disable Driver Auto-Installs & Bloatware'
    Write-Host ' [2]  System : Block ASUS Services & WPBT BIOS Injections'
    Write-Host ' [3]  System : Block Telemetry & Compatibility Appraiser'
    Write-Host ' [4]  Dev    : Install Git, Wget, cURL, VS Code'
    Write-Host ' [5]  Dev    : Install Python 3.12'
    Write-Host ' [6]  Dev    : Android Suite (Platform Tools, Studio)'
    Write-Host ' [7]  Dev    : Visual Studio 2022 + C++/.NET Workloads'
    Write-Host ' [8]  Game   : Install Unity Hub & Godot Engine'
    Write-Host ' [9]  Game   : Gaming Runtimes (VC++, .NET, DirectX, OpenXR)'
    Write-Host ' [10] Perf   : Performance Profile (GHelper-aware)'
    Write-Host ' [11] Specs  : PC Hardware Info & Live Resource Monitor'
    Write-Host ' [C]  Compile this script to "Wilko Koolbox.exe" on Desktop'
    Write-Host ' [S]  Status / Health Panel'
    Write-Host ' [U]  Manage: Update All & Uninstall Packages'
    Write-Host ' [A]  Run ALL Install Tasks Above (1-10)'
    Write-Host ' [R]  Reset registry/task changes'
    Write-Host ' [Q]  Quit / Exit'
    Write-Host '=========================================================' -ForegroundColor Cyan
}

function Show-UninstallMenu {
    Clear-Host
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '                 PACKAGE MANAGEMENT MENU                 ' -ForegroundColor White
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host ' [U] Update all packages'
    Write-Host ' [1] Git             [2] Wget          [3] cURL'
    Write-Host ' [4] VS Code         [5] Python 3.12   [6] Platform Tools'
    Write-Host ' [7] Android Studio  [8] Visual Studio [9] Unity Hub'
    Write-Host ' [10] Godot Engine'
    Write-Host ' [B] Back            [Q] Quit'
    Write-Host '=========================================================' -ForegroundColor Cyan
}

function Task-Drivers {
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 1
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Write-Host ' [OK] Driver auto-installs and consumer bloat disabled.' -ForegroundColor Green
    Write-Log 'Task 1 complete'
}

function Task-ASUS {
    Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1
    $services = Get-Service -Name 'ArmouryCrateControlInterface','ASUSSystemAnalysis','ASUSSystemControlService','AsusAppService' -ErrorAction SilentlyContinue
    foreach ($service in $services) {
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "     [i] Disabled: $($service.Name)" -ForegroundColor DarkGray
    }
    if (-not $services) { Write-Host '     [i] No ASUS services detected.' -ForegroundColor DarkGray }
    Write-Host ' [OK] WPBT execution blocked and ASUS services disabled.' -ForegroundColor Green
    Write-Log 'Task 2 complete'
}

function Task-Telemetry {
    Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    foreach ($name in 'DiagTrack','dmwappushservice','WerSvc') {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) {
            Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "     [i] Disabled: $name" -ForegroundColor DarkGray
        }
    }
    foreach ($task in '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser', '\Microsoft\Windows\Application Experience\ProgramDataUpdater') {
        schtasks.exe /change /tn $task /disable 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "Could not disable scheduled task: $task (exit $LASTEXITCODE)" }
    }
    Write-Host ' [OK] Telemetry policy, services, and compatibility tasks configured.' -ForegroundColor Green
    Write-Log 'Task 3 complete'
}

function Task-DevBasics { 'Git.Git','JernejSimoncic.Wget','curl.curl','Microsoft.VisualStudioCode' | ForEach-Object { Invoke-Winget $_ | Out-Null }; Write-Log 'Task 4 complete' }
function Task-Python { Invoke-Winget 'Python.Python.3.12' | Out-Null; Write-Log 'Task 5 complete' }

function Task-Android {
    'Google.PlatformTools','Google.AndroidStudio' | ForEach-Object { Invoke-Winget $_ | Out-Null }
    [Environment]::SetEnvironmentVariable('ANDROID_HOME', (Join-Path $env:LOCALAPPDATA 'Android\Sdk'), 'User')
    Write-Host '     [i] Open Android Studio > SDK Manager to install build tools, NDK, and CMake.' -ForegroundColor Yellow
    Write-Log 'Task 6 complete'
}

function Task-VisualStudio {
    Invoke-Winget 'Microsoft.VisualStudio.2022.Community' | Out-Null
    $setup = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
    $installPath = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
    if (Test-Path -LiteralPath $setup) {
        $args = "modify --installPath `"$installPath`" --add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Workload.Universal --includeRecommended --passive --norestart"
        Start-Process -FilePath $setup -ArgumentList $args
        Write-Host '     [i] Visual Studio workload installer launched.' -ForegroundColor Yellow
    } else {
        Write-Host '     [!] Visual Studio Installer was not found; complete setup through Visual Studio Installer.' -ForegroundColor Yellow
    }
    Write-Log 'Task 7 complete'
}

function Task-GameEngines { 'Unity.UnityHub','GodotEngine.GodotEngine' | ForEach-Object { Invoke-Winget $_ | Out-Null }; Write-Log 'Task 8 complete' }
function Task-GamingRuntimes { 'Microsoft.VCRedist.2015+.x64','Microsoft.VCRedist.2015+.x86','Microsoft.DotNet.DesktopRuntime.8','Microsoft.DirectX','KhronosGroup.OpenXR-Tools' | ForEach-Object { Invoke-Winget $_ | Out-Null }; Write-Log 'Task 9 complete' }

function Task-Performance {
    if (Test-GHelper) { Write-Host ' [i] GHelper is active; only the Windows-side plan will be changed.' -ForegroundColor Cyan }
    $ultimate = powercfg /list | Select-String 'Ultimate Performance'
    if (-not $ultimate) { powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null; $ultimate = powercfg /list | Select-String 'Ultimate Performance' }
    $guid = (($ultimate -split '\s+') -match '^[a-fA-F0-9-]{36}$')[0]
    if (-not $guid) { throw 'Could not locate or create the Ultimate Performance power plan.' }
    powercfg /setactive $guid
    Start-Sleep -Milliseconds 800
    $active = Get-ActivePlanName
    if ($active -like '*Ultimate*') { Write-Host " [OK] Ultimate Performance active: $active" -ForegroundColor Green }
    else { Write-Host " [!] Windows switched to '$active' instead." -ForegroundColor Yellow }
    Set-RegDword 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-RegDword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Write-Log "Task 10 complete (power plan: $active)"
}

function Task-Specs {
    Clear-Host
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host '================ PC SPECS & LIVE MONITOR ================' -ForegroundColor Cyan
    Write-Host (' CPU: {0} ({1} cores / {2} threads)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    Get-CimInstance Win32_VideoController | ForEach-Object { Write-Host (' GPU: {0}' -f $_.Name.Trim()) }
    Write-Host (' RAM: {0:N1} GB' -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB))
    Get-PhysicalDisk | ForEach-Object { Write-Host (' DISK: {0} - {1:N0} GB ({2})' -f $_.FriendlyName, ($_.Size / 1GB), $_.MediaType) }
    Write-Host (' OS: {0} (build {1})' -f $os.Caption, $os.BuildNumber)
    Write-Host (' Power scheme: {0}' -f (Get-ActivePlanName))
    Write-Host "`nLive monitor updates every 2 seconds. Press Q or Escape to stop." -ForegroundColor Magenta
    while ($true) {
        if ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true); if ($key.Key -in 'Q','Escape') { break } }
        $currentOs = Get-CimInstance Win32_OperatingSystem
        $free = [math]::Round(($currentOs.FreePhysicalMemory / $currentOs.TotalVisibleMemorySize) * 100)
        try { $load = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue) } catch { $load = 'n/a' }
        Write-Host ('  CPU {0,3}% | Free RAM {1,3}% | {2}' -f $load, $free, (Get-Date -Format 'HH:mm:ss'))
        Start-Sleep -Seconds 2
    }
    Write-Log 'Task 11 displayed'
}

function Task-Status {
    Clear-Host
    Write-Host '================ KOOLBOX STATUS / HEALTH ================' -ForegroundColor Cyan
    foreach ($entry in @(
        @{ Name = 'Driver search disabled'; Value = (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig') -eq 0 },
        @{ Name = 'Windows Update driver exclusion'; Value = (Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate') -eq 1 },
        @{ Name = 'WPBT execution blocked'; Value = (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution') -eq 1 },
        @{ Name = 'Game Mode enabled'; Value = (Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 1 }
    )) {
        $color = if ($entry.Value) { 'Green' } else { 'Yellow' }
        $mark = if ($entry.Value) { '[OK]' } else { '[--]' }
        Write-Host "$mark $($entry.Name)" -ForegroundColor $color
    }
    Write-Host "`nPower: $(Get-ActivePlanName)"
    Write-Host ('GHelper: {0}' -f $(if (Test-GHelper) { 'active' } else { 'not detected' }))
    Write-Host "`nPackages:" -ForegroundColor Magenta
    $checks = @{
        'Git' = { Get-Command git -ErrorAction SilentlyContinue }
        'Python' = { Get-Command python -ErrorAction SilentlyContinue }
        'VS Code' = { Get-Command code -ErrorAction SilentlyContinue }
        'Android Platform Tools' = { Get-Command adb -ErrorAction SilentlyContinue }
        'Unity Hub' = { Find-InstalledApp 'Unity Hub' }
        'Godot Engine' = { Find-InstalledApp 'Godot' }
    }
    foreach ($name in $checks.Keys | Sort-Object) {
        $present = $null -ne (& $checks[$name])
        Write-Host ("{0} {1}" -f $(if ($present) { '[OK]' } else { '[--]' }), $name) -ForegroundColor $(if ($present) { 'Green' } else { 'Yellow' })
    }
    Write-Host "`nLog: $(if ($script:LoggingEnabled) { $script:LogFile } else { 'disabled' })" -ForegroundColor DarkGray
    Write-Log 'Status panel displayed'
    Read-Host 'Press Enter to return'
}

function Task-UpdateAll {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget is not available.' }
    winget.exe upgrade --all --accept-package-agreements --accept-source-agreements
    Write-Log "Update all completed (exit $LASTEXITCODE)"
}

function Task-Compile {
    if (-not (Get-Module -ListAvailable -Name ps2exe)) { Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop }
    Import-Module ps2exe -ErrorAction Stop
    $source = $PSCommandPath
    if (-not $source -or $source -match '\.exe$') { Write-Host ' [!] Compilation requires the .ps1 source file.' -ForegroundColor Yellow; return }
    $destination = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Wilko Koolbox.exe'
    Invoke-ps2exe -InputFile $source -OutputFile $destination -RequireAdmin -Title 'Wilko Koolbox' -Description 'All-In-One Dev & Gaming Environment' -ErrorAction Stop
    Write-Host " [OK] Compiled: $destination" -ForegroundColor Green
    Write-Log "Compiled executable: $destination"
}

function Task-Reset {
    Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 1
    foreach ($item in @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'ExcludeWUDriversInQualityUpdate' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures' },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name = 'DisableWpbtExecution' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry' },
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled' },
        @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled' }
    )) { Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue }
    foreach ($task in '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser', '\Microsoft\Windows\Application Experience\ProgramDataUpdater') { schtasks.exe /change /tn $task /enable 2>$null | Out-Null }
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null
    Write-Host ' [OK] Registry, scheduled-task, and power-plan changes reset. Service startup types are left unchanged.' -ForegroundColor Green
    Write-Log 'Reset complete'
}

function Invoke-UninstallChoice {
    param([string]$Choice)
    $packages = @{ '1'='Git.Git'; '2'='JernejSimoncic.Wget'; '3'='curl.curl'; '4'='Microsoft.VisualStudioCode'; '5'='Python.Python.3.12'; '6'='Google.PlatformTools'; '7'='Google.AndroidStudio'; '9'='Unity.UnityHub'; '10'='GodotEngine.GodotEngine' }
    if ($Choice -eq '8') {
        $setup = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
        if (Test-Path -LiteralPath $setup) { Start-Process -FilePath $setup } else { Write-Host '     [!] Visual Studio Installer not found.' -ForegroundColor Yellow }
    } elseif ($packages.ContainsKey($Choice)) { Invoke-Winget -Id $packages[$Choice] -Uninstall | Out-Null }
}

Initialize-Logging

$actions = [ordered]@{
    '1' = @{ Name = 'Driver configuration'; Command = { Task-Drivers } }
    '2' = @{ Name = 'ASUS/WPBT configuration'; Command = { Task-ASUS } }
    '3' = @{ Name = 'Telemetry configuration'; Command = { Task-Telemetry } }
    '4' = @{ Name = 'Developer tools'; Command = { Task-DevBasics } }
    '5' = @{ Name = 'Python'; Command = { Task-Python } }
    '6' = @{ Name = 'Android tools'; Command = { Task-Android } }
    '7' = @{ Name = 'Visual Studio'; Command = { Task-VisualStudio } }
    '8' = @{ Name = 'Game engines'; Command = { Task-GameEngines } }
    '9' = @{ Name = 'Gaming runtimes'; Command = { Task-GamingRuntimes } }
    '10' = @{ Name = 'Performance profile'; Command = { Task-Performance } }
    '11' = @{ Name = 'Hardware monitor'; Command = { Task-Specs } }
    'C' = @{ Name = 'Compile executable'; Command = { Task-Compile } }
    'S' = @{ Name = 'Status panel'; Command = { Task-Status } }
    'R' = @{ Name = 'Reset'; Command = { Task-Reset } }
}

do {
    Show-Menu
    $choice = (Read-Host "`nEnter selection(s), separated by commas").Trim()
    if ($choice -ieq 'Q') { break }

    if ($choice -ieq 'U') {
        do {
            Show-UninstallMenu
            $subChoice = (Read-Host "`nSelect option").Trim()
            if ($subChoice -ieq 'Q') { exit }
            if ($subChoice -ieq 'B') { break }
            try {
                if ($subChoice -ieq 'U') { Task-UpdateAll }
                elseif ($subChoice -match '^(10|[1-9])$') { Invoke-UninstallChoice $subChoice }
                else { Write-Host '     [!] Invalid selection.' -ForegroundColor Yellow }
            } catch { Write-TaskError 'Package management' $_ }
            Read-Host 'Press Enter to continue'
        } while ($true)
        continue
    }

    $requested = if ($choice -ieq 'A') { @('1','2','3','4','5','6','7','8','9','10') } else { $choice.Split(',') }
    foreach ($requestedAction in $requested) {
        $key = $requestedAction.Trim().ToUpperInvariant()
        if (-not $actions.Contains($key)) { Write-Host "     [!] Invalid selection: $key" -ForegroundColor Yellow; continue }
        $action = $actions[$key]
        Write-Host "`n--- $($action.Name) ---" -ForegroundColor Magenta
        try { & $action.Command } catch { Write-TaskError $action.Name $_ }
    }
    Write-Host "`n[OK] Selected tasks complete. Log: $(if ($script:LoggingEnabled) { $script:LogFile } else { 'disabled' })" -ForegroundColor Green
    Read-Host 'Press Enter to return to menu'
} while ($true)