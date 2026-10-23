# Changelog

All notable changes to this project are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

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

[2.1.0]: ../../releases/tag/v2.1.0
[2.0.0]: ../../releases/tag/v2.0.0
