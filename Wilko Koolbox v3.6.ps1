# ============================================================
#  WILKO KOOLBOX v3.7 - All-In-One Dev & Gaming Environment
#  PS 5.1 | GHelper-aware | Triple-layer power detection
#  Changelog v3.7:
#   - Retains v3.5 canonical features and task flow
#   - Adds resilient Desktop -> LOCALAPPDATA -> TEMP logging fallback
#   - Adds checked Winget availability and boolean operation results
#   - Keeps braced task interpolation in error messages
#   - Adds vendor bloat auto-detection for ASUS, HP, Dell, Lenovo, MSI, and Acer
# ============================================================
param()

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        # Raw script: relaunch ourselves elevated via UAC prompt
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        } catch {
            Write-Host "`n[!] Elevation declined or blocked. Exiting." -ForegroundColor Red
            Start-Sleep 2
        }
    } else {
        # Compiled EXE path (should not occur; ps2exe -RequireAdmin handles it)
        Write-Host "`n[!] ERROR: Please run as Administrator." -ForegroundColor Red
        Start-Sleep 3
    }
    Exit
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

# ---------- Install / Uninstall with verification ----------
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
    $benignCodes = @(0, -1978335189, -1978334956, -1978335182)  # no-op / already installed / no upgrade
    if ($LASTEXITCODE -in $benignCodes) {
        Write-Host "     [i] $Id already installed / up to date" -ForegroundColor Gray
        Write-Log "$verb NO-OP (already current): $Id"
        return $true
    }

    Write-Host "     [!] $Id returned exit code $LASTEXITCODE" -ForegroundColor Yellow
    Write-Log "$verb FAILED: $Id (exit $LASTEXITCODE)"
    return $false
}

function Install-Package($id) {
    return Invoke-Winget -Id $id
}

function Uninstall-Package($id) {
    return Invoke-Winget -Id $id -Uninstall
}

# ---------- Helpers ----------
function Set-Reg($path, $name, $value) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value -Type DWord -Force
}

function Test-GHelper {
    return ($null -ne (Get-Process -Name 'GHelper' -ErrorAction SilentlyContinue))
}
function Get-GHelperMode {
    $cfg = Join-Path $env:APPDATA 'GHelper\config.json'
    if (-not (Test-Path -LiteralPath $cfg)) { return $null }
    try {
        $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
        $names = @('Balanced', 'Turbo', 'Silent')
        if ($null -ne $json.mode -and $json.mode -ge 0 -and $json.mode -le 2) { return $names[[int]$json.mode] }
    } catch { }
    return $null
}

function Get-ActivePlanName {
    $line = (powercfg /getactivescheme | Out-String).Trim()
    if ($line -match '\(([^)]+)\)\s*$') { return $Matches[1].Trim() }
    return $line
}

# Registry-based app detection (location-proof, safe from 'commUNITY' trap)
function Find-InstalledApp($displayName) {
    $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
               'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $entries = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue
    foreach ($e in $entries) {
        if ($e.DisplayName -and $e.DisplayName.StartsWith($displayName)) { return $e }
    }
    return $null
}

function Find-InstalledAppLike($pattern) {
    $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($e in (Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue)) {
        if ($e.DisplayName -and ($e.DisplayName -like "*$pattern*")) { return $e }
    }
    return $null
}

Initialize-Logging
# ---------- Menus ----------
function Show-Menu {
    Clear-Host
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '                  WILKO KOOLBOX v3.7                     ' -ForegroundColor White
    Write-Host '        All-In-One Dev & Gaming Environment Builder      ' -ForegroundColor DarkGray
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host ' [1]  System : Disable Driver Auto-Installs & Bloatware'
    Write-Host ' [2]  System : Block WPBT BIOS Injection (all vendors)'
    Write-Host ' [3]  System : Block Telemetry & Compatibility Appraiser'
    Write-Host ' [V]  Vendor : Auto-Detect & Remove OEM Bloat (HP/Dell/Lenovo/MSI/Acer/ASUS)'
    Write-Host ' [4]  Dev    : Install Git, Wget, cURL, VS Code'
    Write-Host ' [5]  Dev    : Install Python 3.12'
    Write-Host ' [6]  Dev    : Android Suite (Platform Tools, Studio, SDK)'
    Write-Host ' [7]  Dev    : Visual Studio 2022 + C++/.NET Workloads'
    Write-Host ' [8]  Game   : Install Unity Hub & Godot Engine'
    Write-Host ' [9]  Game   : Gaming Runtimes (VC++, .NET, DirectX, OpenXR)'
    Write-Host ' [10] Perf   : Performance Profile (GHelper-aware)'
    Write-Host ' [11] Specs  : PC Hardware Info & Live Resource Monitor'
    Write-Host ' [C]  Compile this script to "Wilko Koolbox.exe" on Desktop'
    Write-Host ' [S]  Status / Health Panel (check what is installed)'
    Write-Host ' [U]  Manage: Update All & Uninstall Packages'
    Write-Host ' [A]  Run ALL Install Tasks Above (1-10)'
    Write-Host ' [R]  Reset / Undo System Changes'
    Write-Host ' [Q]  Quit / Exit'
    Write-Host '=========================================================' -ForegroundColor Cyan
}

function Show-UninstallMenu {
    Clear-Host
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '                 PACKAGE MANAGEMENT MENU                 ' -ForegroundColor White
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host ' UPDATE ALL INSTALLED PACKAGES'
    Write-Host ' [U]  winget upgrade --all (update everything)'
    Write-Host ''
    Write-Host ' UNINSTALL INDIVIDUAL PACKAGES:' -ForegroundColor Magenta
    Write-Host ' [1]  Git'
    Write-Host ' [2]  Wget'
    Write-Host ' [3]  cURL'
    Write-Host ' [4]  VS Code'
    Write-Host ' [5]  Python 3.12'
    Write-Host ' [6]  Android Platform Tools'
    Write-Host ' [7]  Android Studio'
    Write-Host ' [8]  Visual Studio 2022 (opens VS Installer)'
    Write-Host ' [9]  Unity Hub'
    Write-Host ' [10] Godot Engine'
    Write-Host ''
    Write-Host ' [B]  Back to Main Menu'
    Write-Host ' [Q]  Quit'
    Write-Host '=========================================================' -ForegroundColor Cyan
}

# ---------- Task functions ----------
function Task-Drivers {
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Write-Host ' [OK] Driver auto-installs and consumer bloat disabled' -ForegroundColor Green
    Write-Log 'Task 1: Driver auto-installs and consumer bloat disabled'
}

function Task-WPBT {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1
    Write-Host ' [OK] WPBT BIOS execution blocked (applies to all vendors)' -ForegroundColor Green
    Write-Log 'Task 2: WPBT execution blocked (generic)'
}
# ---------- Vendor Bloat Module (v3.7) ----------
function Get-MachineManufacturer {
    $mfg = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    if ([string]::IsNullOrWhiteSpace($mfg)) { return 'Unknown' }
    return ($mfg -replace '\s+', ' ').Trim()
}

function Test-VendorDetected {
    param([Parameter(Mandatory)][string]$VendorPattern)
    return (Get-MachineManufacturer) -match "(?i)$VendorPattern"
}

function Disable-VendorServices {
    param(
        [Parameter(Mandatory)][string]$VendorName,
        [Parameter(Mandatory)][string[]]$ServiceNames
    )
    if (-not (Test-VendorDetected $VendorName)) {
        Write-Host "     [i] $VendorName hardware not detected - skipping" -ForegroundColor Gray
        Write-Log "VendorTask: $VendorName skipped (hardware not detected)"
        return
    }
    $found = 0
    foreach ($svc in $ServiceNames) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "     [i] Disabled: $($service.Name)" -ForegroundColor DarkGray
            Write-Log "VendorTask: $($service.Name) disabled"
            $found++
        }
    }
    if ($found -eq 0) {
        Write-Host "     [i] No $VendorName bloat services found" -ForegroundColor DarkGray
    } else {
        Write-Host " [OK] $VendorName bloat disabled ($found services)" -ForegroundColor Green
        Write-Log "VendorTask: $VendorName complete ($found services)"
    }
}

function Task-VendorBloat {
    $mfg = Get-MachineManufacturer
    Write-Host " [i] Detected manufacturer: $mfg" -ForegroundColor Cyan
    Disable-VendorServices -VendorName 'ASUS|ASUSTeK' -ServiceNames @('ArmouryCrateControlInterface','ASUSSystemAnalysis','ASUSSystemControlService','AsusAppService')
    Disable-VendorServices -VendorName 'HP|Hewlett-Packard' -ServiceNames @('HpTouchpointAnalyticsService','HPAppHelperCap','HPDiagsCap','HPSysInfoCap','hpsysdrv')
    Disable-VendorServices -VendorName 'Dell' -ServiceNames @('Dell SupportAssistAgent','DellTechHub','DPMConnector','DellDigitalDelivery','SupportAssistAgent')
    Disable-VendorServices -VendorName 'Lenovo' -ServiceNames @('ImControllerService','LenovoVantageService','LenovoUtilityService')
    Disable-VendorServices -VendorName 'MSI|Micro-Star' -ServiceNames @('MSIService','MSI_Center_Service')
    Disable-VendorServices -VendorName 'Acer' -ServiceNames @('Acer Care Center Service','AcerJumpStart','Acer Quick Access')
}

function Task-Telemetry {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    # v3.5 UPGRADE: Stop telemetry services + disable appraiser scheduled tasks
    @('DiagTrack','dmwappushservice','WerSvc') | ForEach-Object {
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
        Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "     [i] Stopped: $_" -ForegroundColor DarkGray
    }
    foreach ($task in '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser', '\Microsoft\Windows\Application Experience\ProgramDataUpdater') {
        schtasks /change /tn $task /disable 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "Could not disable scheduled task: $task (exit $LASTEXITCODE)" }
    }
    Write-Host ' [OK] Telemetry services/stops + scheduled tasks disabled' -ForegroundColor Green
    Write-Log 'Task 3: Telemetry (registry + services + tasks) disabled'
}

function Task-DevBasics {
    Install-Package 'Git.Git'
    Install-Package 'JernejSimoncic.Wget'
    Install-Package 'curl.curl'
    Install-Package 'Microsoft.VisualStudioCode'
    Write-Log 'Task 4: Dev basics attempted'
}

function Task-Python {
    Install-Package 'Python.Python.3.12'
    Write-Log 'Task 5: Python 3.12 attempted'
}

function Task-Android {
    Install-Package 'Google.PlatformTools'
    Install-Package 'Google.AndroidStudio'
    Write-Host '     [i] After first launch of Android Studio, open SDK Manager to install NDK/CMake/build-tools' -ForegroundColor Yellow
    Start-Process cmd -ArgumentList '/c setx ANDROID_HOME "%LOCALAPPDATA%\Android\Sdk"' -Wait -WindowStyle Hidden
    Write-Log 'Task 6: Android suite attempted'
}

function Task-VisualStudio {
    Install-Package 'Microsoft.VisualStudio.2022.Community'
    $vsSetup = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
    if (Test-Path $vsSetup) {
        $vsArgs = 'modify --installPath "C:\Program Files\Microsoft Visual Studio\2022\Community" --add Microsoft.VisualStudio.Workload.ManagedDesktop --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Workload.Universal --includeRecommended --passive --norestart'
        Write-Host '     [i] VS Installer launching (watch its progress window)...' -ForegroundColor Yellow
        Start-Process -FilePath $vsSetup -ArgumentList $vsArgs
    } else {
        Write-Host '     [!] VS Installer not found - finish setup via winget above or manually' -ForegroundColor Yellow
    }
    Write-Log 'Task 7: Visual Studio workloads queued'
}

function Task-GameEngines {
    Install-Package 'Unity.UnityHub'
    Install-Package 'GodotEngine.GodotEngine'
    Write-Log 'Task 8: Game engines attempted'
}

function Task-GamingRuntimes {
    Install-Package 'Microsoft.VCRedist.2015+.x64'
    Install-Package 'Microsoft.VCRedist.2015+.x86'
    Install-Package 'Microsoft.DotNet.DesktopRuntime.8'
    Install-Package 'Microsoft.DirectX'
    # v3.5 UPGRADE: OpenXR for VR support
    Install-Package 'KhronosGroup.OpenXR-Tools'
    Write-Log 'Task 9: Gaming runtimes + VR support attempted'
}

function Task-Performance {
    if (Test-GHelper) {
        Write-Host ' [i] GHelper detected - it owns CPU/GPU/fan profiles.' -ForegroundColor Cyan
        Write-Host '     Setting Windows-side scheme only (GHelper keeps its own Turbo/Silent profiles).' -ForegroundColor DarkGray
    }
    # Find existing Ultimate Performance plan FIRST (don't duplicate blindly)
    $existingPlan = powercfg /list | Select-String 'Ultimate Performance'
    if (-not $existingPlan) {
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
        $existingPlan = powercfg /list | Select-String 'Ultimate Performance'
    }
    # Extract GUID by regex (format/locale-proof)
    $guid = (($existingPlan -split '\s+') -match '^[a-f0-9-]{36}$')[0]
    if (-not $guid) {
        if (Test-GHelper) {
            Write-Host ' [i] Ultimate Performance plan unavailable on this OS image - GHelper governs hardware performance anyway.' -ForegroundColor Cyan
        } else {
            Write-Host ' [!] Could not locate/create Ultimate Performance plan' -ForegroundColor Yellow
        }
        Write-Log "Task 10: power plan unavailable (GHelper active: $(Test-GHelper)); Game Mode/DVR settings still applied"
        Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Write-Host ' [OK] Game Mode enabled, Game DVR disabled.' -ForegroundColor Green
        return
    }
    powercfg /setactive $guid
    # VERIFY the switch actually stuck (GHelper or group policy can revert it)
    Start-Sleep -Milliseconds 800
    $now = Get-ActivePlanName
    if ($now -like '*Ultimate*') {
        Write-Host " [OK] Ultimate Performance scheme ACTIVE (verified: '$now')" -ForegroundColor Green
    } else {
        Write-Host " [!] Scheme is now '$now' - something reverted the switch." -ForegroundColor Yellow
        if (Test-GHelper) {
            Write-Host '     GHelper manages the Windows scheme per its profile. If it resets to' -ForegroundColor Yellow
            Write-Host '     Balanced, set your preferred Windows plan inside GHelper (Main Settings),' -ForegroundColor Yellow
            Write-Host '     OR accept Balanced + Best Performance slider - hardware perf is unaffected' -ForegroundColor Yellow
            Write-Host '     because GHelper Turbo governs the CPU/fans at firmware level.' -ForegroundColor Yellow
        }
    }
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Write-Log "Task 10: Performance profile applied (scheme: $now)"
    Write-Host ' [OK] Performance profile applied.' -ForegroundColor Green
}

function Task-Specs {
    Clear-Host
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '               PC SPECS & LIVE MONITOR                   ' -ForegroundColor White
    Write-Host '=========================================================' -ForegroundColor Cyan

    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = Get-CimInstance Win32_VideoController
    $ram = Get-CimInstance Win32_ComputerSystem
    $disks = Get-PhysicalDisk
    $bat = Get-CimInstance Win32_Battery
    $os = Get-CimInstance Win32_OperatingSystem

    Write-Host "`n HARDWARE" -ForegroundColor Magenta
    Write-Host (' CPU: {0} ({1} cores / {2} threads)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    foreach ($g in $gpus) {
        $vram = $null
        $cleanName = $g.Name.Trim()
        $idx = 0
        while ($idx -lt 16) {
            try {
                $regKey = Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\{0:d4}' -f $idx) -ErrorAction Stop
                $desc = "$($regKey.DriverDesc)".Trim()
                if ($desc -and $cleanName -and ($desc -like "*$cleanName*" -or $cleanName -like "*$desc*")) {
                    if ($regKey.'HardwareInformation.qwMemorySize') { $vram = [math]::Round($regKey.'HardwareInformation.qwMemorySize' / 1GB); break }
                    if ($regKey.'HardwareInformation.MemorySize')   { $vram = [math]::Round($regKey.'HardwareInformation.MemorySize' / 1GB); break }
                }
            } catch { }
            $idx++
        }
        if ($vram) { Write-Host (' GPU: {0} ({1} GB VRAM)' -f $g.Name.Trim(), $vram) }
        else       { Write-Host (' GPU: {0}' -f $g.Name.Trim()) }
    }
    Write-Host (' RAM: {0:N1} GB total' -f ($ram.TotalPhysicalMemory / 1GB))
    foreach ($d in $disks) { Write-Host (' DISK: {0} - {1:N0} GB ({2})' -f $d.FriendlyName, ($d.Size / 1GB), $d.MediaType) }
    if ($bat.EstimatedChargeRemaining) { Write-Host (' BATTERY: {0}%' -f $bat.EstimatedChargeRemaining) }
    Write-Host (' OS: {0} (build {1})' -f $os.Caption, $os.BuildNumber)

    Write-Host "`n POWER LAYERS" -ForegroundColor Magenta
    Write-Host ' Performance manager: ' -NoNewline
    if (Test-GHelper) {
        $ghMode = Get-GHelperMode
        if ($ghMode) { Write-Host "GHelper (active, $ghMode profile - firmware level)" -ForegroundColor Green }
        else         { Write-Host 'GHelper (active - firmware level)' -ForegroundColor Green }
    } else { Write-Host 'Windows native' -ForegroundColor Yellow }
    Write-Host (' Windows power scheme: {0}' -f (Get-ActivePlanName))
    Write-Host ' Windows power slider (overlay): Settings > System > Power' -ForegroundColor DarkGray

    Write-Host "`n LIVE MONITOR (updates every 2s - press Q to stop)" -ForegroundColor Magenta

    $interactive = $true
    try { $null = [Console]::KeyAvailable } catch { $interactive = $false }
    if (-not $interactive) { Write-Host ' (Console not interactive - press Ctrl+C to stop)' -ForegroundColor DarkGray }

    $nextSample = (Get-Date)
    :monitor while ($true) {
        if ($interactive -and [Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape') { break }
        }
        if ((Get-Date) -ge $nextSample) {
            $cpuLoad = 0
            try {
                $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
                $cpuLoad = [math]::Round($c.CounterSamples[0].CookedValue)
            } catch { $cpuLoad = -1 }
            $os2 = Get-CimInstance Win32_OperatingSystem
            $freePct = [math]::Round(($os2.FreePhysicalMemory / $os2.TotalVisibleMemorySize) * 100)
            $stamp = Get-Date -Format 'HH:mm:ss'
            $line = if ($cpuLoad -ge 0) { (' CPU {0,3}%  |  Free RAM {1,3}%  |  {2}  ' -f $cpuLoad, $freePct, $stamp) }
                    else              { (' CPU  n/a |  Free RAM {0,3}%  |  {1}  ' -f $freePct, $stamp) }
            [Console]::Write("`r{0,-70}" -f $line)
            $nextSample = (Get-Date).AddSeconds(2)
        }
        Start-Sleep -Milliseconds 150
    }
    [Console]::WriteLine('')
    Write-Host ' [i] Monitor stopped - returning to menu' -ForegroundColor DarkGray
    Write-Log 'Task 11: Specs and monitor displayed'
}

function Task-UpdateAll {
    Write-Host ' [*] Updating all installed packages...' -ForegroundColor Yellow
    winget upgrade --all --accept-package-agreements --accept-source-agreements
    Write-Log "Update All: packages upgraded (exit $LASTEXITCODE)"
}

# ---------- Status panel ----------
function Task-Status {
    Clear-Host
    Write-Host '=========================================================' -ForegroundColor Cyan
    Write-Host '               KOOLBOX STATUS / HEALTH PANEL             ' -ForegroundColor White
    Write-Host '=========================================================' -ForegroundColor Cyan

    function Get-RegVal($path, $name) {
        if (Test-Path $path) { return (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }
        return $null
    }
    function Mark($condition) {
        if ($condition) { Write-Host ' [OK]' -ForegroundColor Green -NoNewline } else { Write-Host ' [--]' -ForegroundColor Yellow -NoNewline }
    }

    Write-Host "`n SYSTEM TWEAKS" -ForegroundColor Magenta
    Mark ((Get-RegVal 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig') -eq 0)
    Write-Host ' Driver auto-install search disabled'
    Mark ((Get-RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate') -eq 1)
    Write-Host ' Drivers excluded from Windows Update'
    Mark ((Get-RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures') -eq 1)
    Write-Host ' Consumer features / bloatware disabled'
    Mark ((Get-RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution') -eq 1)
    Write-Host ' WPBT BIOS injections blocked'

    $svcList = Get-Service -Name 'ArmouryCrateControlInterface','ASUSSystemAnalysis','ASUSSystemControlService','AsusAppService' -ErrorAction SilentlyContinue
    $asusRunning = 0
    foreach ($s in $svcList) { if ($s.Status -eq 'Running') { $asusRunning++ } }
    Write-Host ' Vendor (ASUS) services: ' -NoNewline
    if ($asusRunning -gt 0) { Write-Host "$asusRunning still RUNNING (run task V)" -ForegroundColor Red } else { Write-Host ' none running / none found' -ForegroundColor Green }
    Write-Host (' Detected manufacturer: {0}' -f (Get-MachineManufacturer))

    $telem = Get-RegVal 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    Write-Host ' Telemetry policy: ' -NoNewline
    if ($null -ne $telem) { Write-Host "AllowTelemetry=$telem" -ForegroundColor Green } else { Write-Host 'not set (task 3 pending)' -ForegroundColor Yellow }

    Write-Host "`n POWER & GAMING" -ForegroundColor Magenta
    $plan = Get-ActivePlanName
    $ghelperOn = Test-GHelper
    Write-Host ' Windows power scheme: ' -NoNewline
    if ($plan -like '*Ultimate*') {
        Write-Host "$plan [OK]" -ForegroundColor Green
    } elseif ($ghelperOn) {
        Write-Host "$plan (managed by GHelper - its profile sets the scheme)" -ForegroundColor Cyan
    } else {
        Write-Host "$plan (run task 10 for Ultimate Performance)" -ForegroundColor Yellow
    }
    if ($ghelperOn) {
        $ghMode = Get-GHelperMode
        if ($ghMode) { Write-Host " Performance manager: GHelper (active, $ghMode profile - firmware level)" -ForegroundColor Green }
        else         { Write-Host ' Performance manager: GHelper (active - firmware level)' -ForegroundColor Green }
        Write-Host ' Info: the Settings > Power slider is a separate layer ON TOP of the scheme.' -ForegroundColor DarkGray
        Write-Host '       Balanced + Best Performance + GHelper Turbo = max perf anyway.' -ForegroundColor DarkGray
    }
    Mark ((Get-RegVal 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 1)
    Write-Host ' Game Mode enabled'

    Write-Host "`n DEV TOOLS & PACKAGES" -ForegroundColor Magenta
    $pkgChecks = @(
        @{ id='Git';       test={ $null -ne (Get-Command git -ErrorAction SilentlyContinue) } },
        @{ id='Wget';      test={ $null -ne (Get-Command wget -ErrorAction SilentlyContinue) } },
        @{ id='cURL';      test={ $null -ne (Get-Command curl -ErrorAction SilentlyContinue) } },
        @{ id='Python';    test={ $null -ne (Get-Command python -ErrorAction SilentlyContinue) } },
        @{ id='adb (Android Platform Tools)'; test={ $null -ne (Get-Command adb -ErrorAction SilentlyContinue) } },
        @{ id='Android Studio'; test={ Test-Path 'C:\Program Files\Android\Android Studio\bin\studio64.exe' } },
        @{ id='Unity (Hub/Editor)'; test={ ($null -ne (Find-InstalledAppLike 'Unity')) -or (Test-Path "$env:LOCALAPPDATA\Programs\Unity Hub\Unity Hub.exe") -or (Test-Path "C:\Program Files\Unity Hub\Unity Hub.exe") } },
        @{ id='Godot Engine'; test={ ($null -ne (Get-Command godot -ErrorAction SilentlyContinue)) -or ($null -ne (Find-InstalledApp 'Godot')) } },
        @{ id='VS Code';   test={ $null -ne (Get-Command code -ErrorAction SilentlyContinue) } },
        @{ id='Visual Studio 2022'; test={ Test-Path 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe' } }
    )
    foreach ($p in $pkgChecks) { Mark (& $p.test); Write-Host " $($p.id)" }

    Write-Host "`n WINDOWS EDITION INFO" -ForegroundColor Magenta
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host (' OS: {0} (build {1})' -f $os.Caption, $os.BuildNumber)

    Write-Host "`n=========================================================" -ForegroundColor Cyan
    Write-Log 'Status panel displayed'
    Read-Host 'Press Enter to return to menu'
}

# ---------- Compile ----------
function Task-Compile {
    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    }
    $mod = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
    if ($mod) {
        $ps2exePath = Join-Path $mod.ModuleBase 'ps2exe.ps1'
        if (Test-Path $ps2exePath) {
            $content = Get-Content $ps2exePath -Raw
            if ($content -match '-Encoding UTF8') {
                Set-Content -Path $ps2exePath -Value ($content -replace '-Encoding UTF8', '') -Force
            }
        }
    }
    $src = $PSCommandPath
    $dest = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'Wilko Koolbox.exe')
    if ($src -and ($src -notmatch '\.exe$')) {
        Write-Host "Compiling to $dest ..." -ForegroundColor Yellow
        Invoke-ps2exe -InputFile $src -OutputFile $dest -RequireAdmin -Title 'Wilko Koolbox' -Description 'All-In-One Dev & Gaming Environment'
        Write-Log 'Compiled: Wilko Koolbox.exe'
    } else {
        Write-Host '     [!] Already running as EXE - nothing to compile.' -ForegroundColor Yellow
    }
}

# ---------- Reset ----------
function Task-Reset {
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 1 -Type DWord -Force
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' -ErrorAction SilentlyContinue
    schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable 2>$null | Out-Null
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null
    Write-Host ' [OK] System changes reverted (restart recommended)' -ForegroundColor Green
    Write-Log 'Reset: system changes undone'
}

# ---------- Dispatch ----------
function Invoke-UninstallChoice($act) {
    switch ($act) {
        '1' { Uninstall-Package 'Git.Git' }
        '2' { Uninstall-Package 'JernejSimoncic.Wget' }
        '3' { Uninstall-Package 'curl.curl' }
        '4' { Uninstall-Package 'Microsoft.VisualStudioCode' }
        '5' { Uninstall-Package 'Python.Python.3.12' }
        '6' { Uninstall-Package 'Google.PlatformTools' }
        '7' { Uninstall-Package 'Google.AndroidStudio' }
        '8' {
            Write-Host '     [i] Visual Studio uninstall must be done via its installer GUI.' -ForegroundColor Yellow
            $vsSetup = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
            if (Test-Path $vsSetup) { Start-Process $vsSetup } else { Write-Host '     [!] VS Installer not found' -ForegroundColor Red }
        }
        '9' { Uninstall-Package 'Unity.UnityHub' }
        '10' { Uninstall-Package 'GodotEngine.GodotEngine' }
    }
}

function Invoke-Choice($act) {
    switch ($act) {
        '1'  { Task-Drivers }
        '2'  { Task-WPBT }
        '3'  { Task-Telemetry }
        'V'  { Task-VendorBloat }
        '4'  { Task-DevBasics }
        '5'  { Task-Python }
        '6'  { Task-Android }
        '7'  { Task-VisualStudio }
        '8'  { Task-GameEngines }
        '9'  { Task-GamingRuntimes }
        '10' { Task-Performance }
        '11' { Task-Specs }
        'C'  { Task-Compile }
        'S'  { Task-Status }
        'R'  { Task-Reset }
    }
}

# ---------- Main loop (v3.5 UPGRADE: ordered hashtable dispatcher) ----------
$actions = [ordered]@{
    "1"  = @{ Name = "Disable Driver Auto-Installs & Bloatware";   Cmd = { Task-Drivers } }
    "2"  = @{ Name = "Block WPBT BIOS Injection (all vendors)";    Cmd = { Task-WPBT } }
    "3"  = @{ Name = "Block Telemetry & Compatibility Appraiser"; Cmd = { Task-Telemetry } }
    "V"  = @{ Name = "Vendor Bloat Removal";                       Cmd = { Task-VendorBloat } }
    "4"  = @{ Name = "Install Dev Basics";                       Cmd = { Task-DevBasics } }
    "5"  = @{ Name = "Install Python 3.12";                      Cmd = { Task-Python } }
    "6"  = @{ Name = "Android Suite (Platform Tools, Studio)";   Cmd = { Task-Android } }
    "7"  = @{ Name = "Visual Studio 2022 + C++/.NET Workloads";   Cmd = { Task-VisualStudio } }
    "8"  = @{ Name = "Install Unity Hub & Godot Engine";         Cmd = { Task-GameEngines } }
    "9"  = @{ Name = "Gaming Runtimes (VC++, .NET, DirectX)";     Cmd = { Task-GamingRuntimes } }
    "10" = @{ Name = "Performance Profile (GHelper-aware)";     Cmd = { Task-Performance } }
    "11" = @{ Name = "PC Hardware Info & Live Monitor";         Cmd = { Task-Specs } }
    "C"  = @{ Name = "Compile to Wilko Koolbox.exe";            Cmd = { Task-Compile } }
    "S"  = @{ Name = "Status / Health Panel";                   Cmd = { Task-Status } }
    "R"  = @{ Name = "Reset / Undo System Changes";             Cmd = { Task-Reset } }
}

do {
    Show-Menu
    $choice = (Read-Host "`nEnter selection(s) separated by commas (e.g. 1,2,S or A)").Trim()
    if ($choice -eq 'Q' -or $choice -eq 'q') { Exit }

    if ($choice -ieq 'U') {
        do {
            Show-UninstallMenu
            $sub = (Read-Host "`nSelect option").Trim()
            if ($sub -ieq 'B') { break }
            if ($sub -ieq 'Q') { Exit }
            if ($sub -ieq 'U') { Task-UpdateAll }
            elseif ($sub -match '^([1-9]|10)$') { Invoke-UninstallChoice $sub }
        } while ($true)
    }
    elseif ($choice -ieq 'A') {
        foreach ($t in 1..10) {
            Write-Host "`n--- Running task $t ---" -ForegroundColor Magenta
            try { Invoke-Choice "$t" } catch { Write-Host "     [!] Task ${t} errored: $($_.Exception.Message)" -ForegroundColor Red; Write-Log "ERROR task ${t}: $($_.Exception.Message)" }
        }
        Write-Host "`n[OK] All tasks complete! (log saved to Desktop\Koolbox.log)" -ForegroundColor Green
        Read-Host 'Press Enter to return to menu'
    }
    else {
        $inputActions = $choice.Split(',')
        foreach ($act in $inputActions) {
            $a = $act.Trim()
            if ([string]::IsNullOrWhiteSpace($a)) { continue }
            Write-Host "`n--- Running task $a ---" -ForegroundColor Magenta
            try { Invoke-Choice $a } catch { Write-Host "     [!] Task ${a} errored: $($_.Exception.Message)" -ForegroundColor Red; Write-Log "ERROR task ${a}: $($_.Exception.Message)" }
        }
        Write-Host "`n[OK] Tasks complete! (log saved to Desktop\Koolbox.log)" -ForegroundColor Green
        Read-Host 'Press Enter to return to menu'
    }
} while ($true)