# Wilko Koolbox v3.5
Wilko Koolbox is an elevated PowerShell menu for configuring a Windows development and gaming workstation. It combines optional system preferences, developer-tool installation, game-engine setup, runtime installation, power-profile configuration, package management, and basic hardware monitoring.

The main script is `Wilko Koolbox v3.ps1`.

## Features
- Disables Windows driver searching, Windows Update driver delivery, and consumer-feature suggestions.
- Blocks WPBT execution and disables selected ASUS/Armoury Crate services when present.
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
- Run the script from an **Administrator** PowerShell window.
- Internet access for package installation and updates.
- `winget` / App Installer for package-related tasks.
- Access to the PowerShell Gallery only when using the compile option for the first time; it installs `ps2exe` for the current user.

## Usage
1. Save `Wilko Koolbox v3.ps1` locally.
2. Open PowerShell as Administrator.
3. Run the script:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "C:\Users\Administrator\Wilko Koolbox v3.ps1"
```

4. Enter a single menu key, a comma-separated set of keys such as `4,5,8`, or `A` to run installation tasks 1–10.
5. Press `Q` from the main menu to exit.

## Main-menu reference
- `1` — Disable automatic driver delivery and consumer-feature suggestions.
- `2` — Block WPBT execution and disable detected ASUS services.
- `3` — Configure telemetry policies, selected services, and compatibility tasks.
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
- The reset action restores the registry values, compatibility scheduled tasks, and the Balanced Windows power plan managed by Koolbox.
- Review each option before running it, especially the system, ASUS, telemetry, and reset actions.

## Reset limitations
The `R` action does not recreate the system's pre-Koolbox configuration; it reverses only settings that the script can safely identify.

- Driver search is set back to the Windows default value used by Koolbox (`SearchOrderConfig = 1`).
- The Koolbox Windows Update, consumer-feature, WPBT, telemetry, Game Mode, and Game DVR registry values are removed.
- The two compatibility scheduled tasks are re-enabled, and the Windows Balanced power plan is selected.
- **Disabled services are not re-enabled and their prior startup types are not restored.** This applies to the selected ASUS services and telemetry services. If you want a component to run again, restore the appropriate service configuration manually through Services, an OEM utility, or your organization’s standard configuration process.
