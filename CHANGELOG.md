# Changelog

All notable changes to this project are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [2.2.1] - 2026-10-24

### Added
- **FPS counter option for every game, BF6 included.** The script now asks "Show the FPS counter inside the game?" (Enter = yes) and writes `PerfOverlay.DrawFps 1` to `user.cfg`. In the GUI the checkbox is shown for BF6 too and is on by default. It is known to work in BF4, BF1 and BF V; it is not confirmed for BF6, where the game simply ignores an unknown command.

### Changed
- The BF6 experimental extra is now only `Thread.MaxWorkerThreadCount`; the FPS counter moved to the regular option above.
- Saying no to the FPS counter writes nothing, unless your existing `user.cfg` turns the counter on: then `PerfOverlay.DrawFps 0` replaces that line, so the counter really goes off. (Before, the script always wrote the counter for BF4 / BF1 / BF V, and an unticked GUI box left an old line in place.)
- **The version is now part of the file names:** `Battlefield_Optimizer_v2.2.1.cmd` and `Battlefield_Optimizer_GUI_v2.2.1.cmd`. The script's `G` menu entry finds the GUI by the pattern `Battlefield_Optimizer_GUI*.cmd`, and the GUI finds the script by `Battlefield_Optimizer*.cmd`; when several copies are in the folder, the highest version wins. Delete older copies when you update.
- Script and GUI version numbers are now 2.2.1. The GUI needs script 2.2.1 or newer.

## [2.2.0] - 2026-10-24

### Added
- **GUI remembers your choices** between runs (game, tier, tweak groups, FPS cap and user.cfg options), saved in `%APPDATA%\Battlefield Optimizer\gui-settings.json`. New **Reset choices** button.
- **GUI tweak groups** now show how many settings each one holds for the selected game and tier; hovering lists them, and groups the game doesn't have (for example lens effects in BF4) are greyed out.
- **GUI report** now includes what the script already printed: RAM and refresh-rate warnings, in-game refresh-rate warning, DirectX 12 / DXR and DLSS hints, the graphics-driver settings, and the GUI and script versions. It is shown from the top, and saved to `README.txt`.
- **GUI Undo** shows the date of each backup (or that the file will be removed) before restoring.
- **BF6 experimental extras (optional, off by default)** in the script and the GUI: `PerfOverlay.DrawFps 1` and `Thread.MaxWorkerThreadCount <threads>`. No public source confirms them for BF6, so they are never part of the default output.
- Link to the project page in the GUI.

### Fixed
- **Outdated profile.** The games rewrite `PROFSAVE_profile` when they exit, so a file generated while the game was open could overwrite changes made in that session. The GUI now waits for the game to close before generating; the script asks you to close it first (type `C` to continue anyway, and it then rebuilds the profile from the game's saved copy before applying).
- **Laptops with two GPUs:** the dedicated GPU (NVIDIA, Radeon RX / Pro, Arc A / B) is now preferred over an integrated Radeon or Intel GPU, even when the integrated one reports more memory.
- **GUI engine choice:** when several `Battlefield_Optimizer*.cmd` files are in the folder, the one with the highest version is used (before, the name that sorted last won, which could be an old versioned file). A script older than the GUI is refused with a clear message.
- **GUI "No limit"** for BF4, BF1 and BF V wrote `GameTime.MaxVariableFps 0`, whose meaning is not documented. It now writes `999`.

### Changed
- Driver advice, hardware warnings and the BF6 extras live in the script and are shared with the GUI, so both print the same text.
- Laptop RTX 5060 is treated like the 4060 laptop in the Battlefield 6 GPU tiers (Medium).
- Script and GUI version numbers are now 2.2.0. The GUI needs script 2.2.0 or newer.

## [2.1.0] - 2026-10-23

### Added
- **Windows GUI:** new `Battlefield_Optimizer_GUI.cmd`, a window version of the optimizer. It needs no install (Windows PowerShell 5.1 and WinForms, both included with Windows).
  - Choose the game (Battlefield 4, 1, V or 6), with install and settings status.
  - Choose the graphics tier: **Auto** (from the detected GPU) or force Low, Medium or High.
  - Tick or untick each tweak group: motion blur, lens effects, depth of field, visibility, costly effects, in-game V-Sync, BF6 frame generation and low-latency modes, BF1 DirectX 11, and the GPU-tier graphics preset. Unticked groups are left exactly as they are in your profile.
  - Set the FPS cap to **Auto** (same formula as the script), a **custom value** or **no limit**, with the result and the reason shown live.
  - Choose which `user.cfg` lines are written: FPS counter, render queue and the V-Sync / triple buffering / motion blur lines (BF4, BF1, BF V), or the CPU thread settings (BF6).
  - Buttons: **Generate files (preview only)**, **Generate and apply** (confirmation, waits for the game to close, backup first), **Undo last apply** and **Open output folder**.
  - Uses the same backup files (`.bak_YYYYMMDD_HHMMSS`) as the script, so you can apply with one and undo with the other.
- **Script menu:** a `G) Graphical interface` entry opens the GUI when `Battlefield_Optimizer_GUI.cmd` is in the same folder.
- **Web page:** now mentions the Windows script and the GUI, with a short section comparing them.
- **Documentation:** new "Option 3: Windows GUI" section, updated comparison table, FAQ, troubleshooting and repository layout in the README. Added this changelog.

### Changed
- The GUI loads the detection and tuning code from `Battlefield_Optimizer.cmd` at start-up instead of keeping a copy, so both always give the same results. The script keeps the `$Games = [ordered]@{` line and the `#  OPTIMIZER RUN (one game)` heading as markers for this; keep them in place when editing.
- Script version number is now 2.1.0. Generation, tuning rules, backups and Undo are unchanged.

## [2.0.0]

### Changed
- One script, `Battlefield_Optimizer.cmd`, for Battlefield 4, Battlefield 1, Battlefield V and Battlefield 6, replacing the earlier per-game scripts.
- Game menu showing whether each game is installed and whether its settings file was found.
- Per-game GPU tiers, graphics values, FPS cap and `user.cfg` contents, with shared hardware detection, file location, backup and Undo code.
- Hardware and display answers are reused when optimizing several games in the same session.

### Added
- Output in a `<game>_Optimized` folder with `user.cfg`, `PROFSAVE_profile` and a `README.txt` report.
- Optional install into the game with a backup of each replaced file, and **Undo** to restore the newest backup.
- Monitor EDID reading for the refresh range and G-Sync / FreeSync hints, confirmed by the user.
- Web page (Config Builder) that builds the same files in the browser.

[2.2.1]: ../../releases/tag/v2.2.1
[2.2.0]: ../../releases/tag/v2.2.0
[2.1.0]: ../../releases/tag/v2.1.0
[2.0.0]: ../../releases/tag/v2.0.0
