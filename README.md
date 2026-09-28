# Wilko Koolbox v3.7

## Quick Start
Download Run-Koolbox.bat and the .ps1 into the same folder, double-click Run-Koolbox.bat, approve the UAC prompt, and the menu appears. Alternative: right-click the .ps1 and choose Run with PowerShell.
Wilko Koolbox is an elevated PowerShell menu for configuring a Windows development and gaming workstation. It combines optional system preferences, developer-tool installation, game-engine setup, runtime installation, power-profile configuration, package management, and basic hardware monitoring.

The main script is `Wilko Koolbox v3.6.ps1`.
## What's new in v3.7
- Adds the Vendor Bloat Module: one `V` menu action detects ASUS, HP, Dell, Lenovo, MSI, or Acer hardware and disables only the matching OEM services.
- Each vendor check self-skips when its hardware manufacturer is not detected, so the same action is safe to run across supported vendors.
- The `V` action includes ASUS service disabling; Task `2` now blocks WPBT BIOS injection independently for every manufacturer.
## What's new in v3.6
- Reconciles the repository with the canonical v3.5 Koolbox source while preserving its full menu, system-task, performance, status-panel, and hardware-monitor functionality.
- Adds resilient activity logging: Koolbox tries the Desktop first, then `%LOCALAPPDATA%\WilkoKoolbox`, then `%TEMP%`; it disables logging gracefully if no destination is writable.
- Adds a checked `Invoke-Winget` wrapper that verifies `winget` is available, returns a success/failure result, and logs package-operation failures.
- Retains the elevation guard, registry-based installed-app detection, find-existing-first Ultimate Performance handling, locale-tolerant GUID parsing, and all 10 status-panel package checks.

## Features
- Disables Windows driver searching, Windows Update driver delivery, and consumer-feature suggestions.
- Blocks WPBT execution for all vendors; the `V` action disables matching ASUS/Armoury Crate services when ASUS hardware is detected.
- Applies telemetry-related registry policies, disables selected telemetry services, and disables compatibility-appraiser tasks.
- Installs developer tools through `winget`:
  - Git, Wget, cURL, and Visual Studio Code
  - Python 3.12
  - Android Platform Tools and Android Studio
  - Visual Studio 2022 Community and desktop workloads
- Installs Unity Hub, Godot Engine, gaming runtimes, DirectX, and OpenXR Tools.
- Enables Game Mode, disables Game DVR, and configures the Ultimate Performance power plan while detecting GHelper.
- Shows a health/status panel and a live CPU/RAM monitor.
- Updates or uninstalls supported packages.
- Can compile itself to `Wilko Koolbox.exe` using `ps2exe`.

## Requirements
- Windows 10 or Windows 11.
- Windows PowerShell 5.1 or newer.
- When run as a raw `.ps1` file, the script automatically relaunches itself with elevation and displays a Windows UAC prompt. Compiled executables use ps2exe's `-RequireAdmin` behavior.
- Internet access for package installation and updates.
- `winget` / App Installer for package-related tasks.
- Access to the PowerShell Gallery only when using the compile option for the first time; it installs `ps2exe` for the current user.
## Installation
1. Download or clone this repository.
2. Keep `Wilko Koolbox v3.6.ps1` in a local folder. The script writes logs outside the repository by default.
3. Open PowerShell or Windows Terminal normally and start the script using the command in the next section.
4. Approve the UAC prompt when Koolbox relaunches itself with elevated permissions.

## Usage
Run the script from PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "C:\path\to\WilkoKoolbox\Wilko Koolbox v3.6.ps1"
```

Enter a single menu key, a comma-separated set of keys such as `4,5,8`, or `A` to run installation tasks 1–10. Press `Q` from the main menu to exit.

## Main-menu reference
- `1` — Disable automatic driver delivery and consumer-feature suggestions.
- `2` — Block WPBT BIOS injection for all vendors.
- `3` — Configure telemetry policies, selected services, and compatibility tasks.
- `V` — Auto-detect the system manufacturer and remove matching ASUS, HP, Dell, Lenovo, MSI, or Acer OEM bloat services.
- `4` — Install Git, Wget, cURL, and VS Code.
- `5` — Install Python 3.12.
- `6` — Install Android Platform Tools and Android Studio.
- `7` — Install Visual Studio Community and queue desktop workloads.
- `8` — Install Unity Hub and Godot Engine.
- `9` — Install VC++ redistributables, .NET Desktop Runtime, DirectX, and OpenXR Tools.
- `10` — Apply the gaming/performance settings.
- `11` — Show hardware details and a live CPU/RAM monitor; press `Q` or `Esc` to stop it.
- `C` — Compile the script to an elevated executable on the Desktop.
- `S` — Display system-tweak, power, package, and logging status.
- `U` — Open package update/uninstall management.
- `A` — Run tasks 1–10 in sequence.
- `R` — Remove the registry/task settings managed by the reset task.

## Logging
Koolbox appends activity and failure records with timestamps. It attempts log locations in this order:
1. `Desktop\Koolbox.log`
2. `%LOCALAPPDATA%\WilkoKoolbox\Koolbox.log`
3. `%TEMP%\Koolbox.log`

If none of these locations can be written, logging is disabled with a warning and the requested task continues. If a later log write fails, logging is likewise disabled rather than causing the task to fail.

## Important behavior and reset
- Package installers may open their own windows or require a first-launch setup step. In particular, install Android build tools, NDK, and CMake from Android Studio's SDK Manager after its first launch.
- GHelper remains the source of truth for its hardware-level CPU, GPU, and fan profiles. The performance task changes only the Windows-side power plan.
- The reset action removes Koolbox-managed registry policies and feature values, re-enables compatibility scheduled tasks, and selects the Balanced Windows power plan.
- Review each option before running it, especially the system, ASUS, telemetry, and reset actions.

## Reset limitations
The `R` action does not recreate the system's pre-Koolbox configuration; it reverses only settings that the script can safely identify.

- Driver search is set back to the Windows default value used by Koolbox (`SearchOrderConfig = 1`).
- The Koolbox Windows Update, consumer-feature, WPBT, telemetry, Game Mode, and Game DVR registry values are removed.
- The two compatibility scheduled tasks are re-enabled, and the Windows Balanced power plan is selected.
- **Disabled services are not re-enabled and their prior startup types are not restored.** This applies to the selected ASUS services and telemetry services. If you want a component to run again, restore the appropriate service configuration manually through Services, an OEM utility, or your organization’s standard configuration process.
