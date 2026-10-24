<# : batch
@echo off
REM ---------------------------------------------------------------------------
REM  Battlefield Optimizer GUI - batch/PowerShell hybrid launcher.
REM  Double-click this file. It starts Windows PowerShell (no console window)
REM  which reads the rest of this file and shows the window.
REM  Keep it in the same folder as Battlefield_Optimizer.cmd: the GUI loads
REM  that script's detection and tuning functions, so both always agree.
REM  ExecutionPolicy Bypass applies to this process only.
REM ---------------------------------------------------------------------------
setlocal
set "BFCFG_SCRIPT=%~f0"
set "BFCFG_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "BFCFG_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%BFCFG_PS%" set "BFCFG_PS=powershell"
start "" "%BFCFG_PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command "iex ([IO.File]::ReadAllText($env:BFCFG_SCRIPT))"
exit /b
#>

# =============================================================================
#  Battlefield Optimizer GUI
#  Pick the game, graphics tier, FPS cap and exactly which tweaks to apply.
#  Nothing is changed on the system until you click "Generate and apply" and
#  confirm. Every apply makes a backup that "Undo last apply" restores.
#  Your choices are remembered between runs (%APPDATA%\Battlefield Optimizer).
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function Show-Error([string]$m) {
    [void][Windows.Forms.MessageBox]::Show($m, 'Battlefield Optimizer GUI', 'OK', 'Error')
}

try {

$scriptDir  = Split-Path -Parent $env:BFCFG_SCRIPT
$GuiVersion = '2.2.1'
$MinEngine  = [version]'2.2.1'      # first script version with the functions this GUI calls
$RepoUrl    = 'https://github.com/j0p3s/battlefield-user-profile-tweaker'
$Latin1     = [Text.Encoding]::GetEncoding(28591)
$Invariant  = [Globalization.CultureInfo]::InvariantCulture
$appData    = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath('ApplicationData') }
$settingsFile = Join-Path $appData 'Battlefield Optimizer\gui-settings.json'

# ---------------------------------------------------------------------------
# Load the engine: everything between the game definitions and the CLI
# "optimizer run" section of the script (hardware detection, file locations,
# backup/restore, profile builders, GPU tiers, tuning values).
# Several copies can sit in the folder (an old versioned name next to the
# current one): the one with the highest AppVersion is used, not the one that
# happens to sort last.
# ---------------------------------------------------------------------------
function Get-EngineVersion([string]$text) {
    $m = [regex]::Match($text, "AppVersion = '(\d+(\.\d+){1,3})'")
    if ($m.Success) { [version]$m.Groups[1].Value } else { [version]'0.0' }
}

$engineText = $null
$engineVer  = [version]'0.0'
foreach ($f in @(Get-ChildItem -LiteralPath $scriptDir -Filter 'Battlefield_Optimizer*.cmd' -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notmatch 'GUI' })) {
    try {
        $t = [IO.File]::ReadAllText($f.FullName)
        if ($t.IndexOf('$Games = [ordered]@{') -lt 0) { continue }
        $v = Get-EngineVersion $t
        if ($null -eq $engineText -or $v -gt $engineVer) { $engineText = $t; $engineVer = $v }
    } catch { }
}
if ($null -eq $engineText) {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Select Battlefield_Optimizer.cmd'
    $dlg.Filter = 'Battlefield Optimizer (*.cmd)|*.cmd'
    if ($dlg.ShowDialog() -ne 'OK') { exit }
    $engineText = [IO.File]::ReadAllText($dlg.FileName)
    $engineVer  = Get-EngineVersion $engineText
}
$a = $engineText.IndexOf('$Games = [ordered]@{')
$b = $engineText.IndexOf('#  OPTIMIZER RUN (one game)')
if ($a -lt 0 -or $b -le $a -or $engineText -notmatch 'function Get-Hardware') {
    throw 'That file is not a compatible Battlefield Optimizer v2 script (engine section not found).'
}
if ($engineVer -lt $MinEngine) {
    throw ("Battlefield_Optimizer.cmd is v{0}, but this GUI (v{1}) needs v{2} or newer.`r`n`r`nDownload the latest script from`r`n{3}/releases/latest`r`nand keep both files in the same folder." -f $engineVer, $GuiVersion, $MinEngine, $RepoUrl)
}
Invoke-Expression $engineText.Substring($a, $b - $a)
$AppVersion = $engineVer.ToString()

# ---------------------------------------------------------------------------
# Tweak categories. Each profile key belongs to the first category whose
# pattern matches it; unticking a category leaves those keys untouched.
# ---------------------------------------------------------------------------
$Cats = @(
    @{ Id = 'mb';  Re = 'MotionBlur';                                   Text = 'Motion blur off' }
    @{ Id = 'len'; Re = 'ChromaticAberration|FilmGrain|LensDistortion|Vignette'; Text = 'Lens effects off (aberration, grain, distortion, vignette)' }
    @{ Id = 'dof'; Re = 'WeaponDOF|SniperSweetspotDoF';                 Text = 'Depth of field off (weapon and scope blur)' }
    @{ Id = 'vis'; Re = 'UndergrowthQuality|PostProcessQuality|VolumetricQuality'; Text = 'Visibility: less grass, bloom/haze, volumetric fog' }
    @{ Id = 'exp'; Re = 'AmbientOcclusion|ScreenSpaceReflections|ReflectionQuality|LocalLightShadowQuality|TransparentShadows|Enlighten|AntiAliasingDeferred'; Text = 'Costly effects off (AO, reflections, GI, deferred MSAA)' }
    @{ Id = 'vs';  Re = 'VSync';                                        Text = 'V-Sync off in game (use driver V-Sync / G-Sync)' }
    @{ Id = 'fg';  Re = 'FrameGeneration|LowLatency';                   Text = 'BF6: frame generation off, low-latency modes on' }
    @{ Id = 'dx';  Re = 'Dx12';                                         Text = 'BF1: force DirectX 11 (less stutter)' }
    @{ Id = 'pre'; Re = '.';                                            Text = 'GPU-tier preset: textures, meshes, shadows, AA...' }
)

function Get-CatId([string]$k) {
    foreach ($c in $Cats) { if ($k -match $c.Re) { return $c.Id } }
    'pre'
}

function Select-Settings($settings) {
    $out = [ordered]@{}
    foreach ($k in $settings.Keys) {
        if ($k -eq 'GstRender.OverallGraphicsQuality') { continue }
        if ($script:cbCat[(Get-CatId $k)].Checked) { $out[$k] = $settings[$k] }
    }
    # "Custom" preset flag, only when something else is being changed
    if ($out.Count -gt 0 -and $settings.Contains('GstRender.OverallGraphicsQuality')) {
        $out['GstRender.OverallGraphicsQuality'] = $settings['GstRender.OverallGraphicsQuality']
    }
    $out
}

# =============================================================================
#  WINDOW
# =============================================================================
$form = New-Object Windows.Forms.Form
$form.Text = "Battlefield Optimizer GUI v$GuiVersion (engine v$AppVersion)"
$form.ClientSize = New-Object Drawing.Size(900, 760)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

$tt = New-Object Windows.Forms.ToolTip
$tt.AutoPopDelay = 25000
$tt.InitialDelay = 400

function New-Group([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $c = New-Object Windows.Forms.GroupBox
    $c.Text = $text
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, $h)
    $form.Controls.Add($c)
    $c
}
function New-Label($parent, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h = 20) {
    $c = New-Object Windows.Forms.Label
    $c.Text = $text
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, $h)
    $parent.Controls.Add($c)
    $c
}
function New-Check($parent, [string]$text, [int]$x, [int]$y, [int]$w = 405, [bool]$checked = $true) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text = $text
    $c.Checked = $checked
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, 22)
    $parent.Controls.Add($c)
    $c
}
function New-Combo($parent, [string[]]$items, [int]$x, [int]$y, [int]$w) {
    $c = New-Object Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    foreach ($i in $items) { [void]$c.Items.Add($i) }
    $c.SelectedIndex = 0
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, 24)
    $parent.Controls.Add($c)
    $c
}
function New-Num($parent, [int]$min, [int]$max, [int]$val, [int]$x, [int]$y, [int]$w = 70) {
    $c = New-Object Windows.Forms.NumericUpDown
    $c.Minimum = $min; $c.Maximum = $max; $c.Value = $val
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, 24)
    $parent.Controls.Add($c)
    $c
}
function New-Btn([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $c = New-Object Windows.Forms.Button
    $c.Text = $text
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, $h)
    $form.Controls.Add($c)
    $c
}

# --- 1. Game ---
$gG = New-Group '1. Game' 10 8 430 62
$cbGame = New-Combo $gG @('Loading...') 15 26 400

# --- Hardware ---
$gH = New-Group 'Detected hardware' 10 74 430 176
$lblHw = New-Label $gH 'Detecting hardware...' 12 20 408 150

# --- 2. Graphics ---
$gP = New-Group '2. Graphics (PROFSAVE_profile)' 10 254 430 322
$cbProfile = New-Check $gP 'Generate PROFSAVE_profile' 15 22 400 $true
New-Label $gP 'Graphics tier:' 32 50 90 | Out-Null
$cbTier = New-Combo $gP @('Auto (from GPU)', 'Low', 'Medium', 'High') 125 47 150
$lblTier = New-Label $gP '' 282 50 140
New-Label $gP 'Tweaks to include (number of settings; hover for the list):' 15 80 410 | Out-Null
$script:cbCat = @{}
$yy = 102
foreach ($c in $Cats) {
    $script:cbCat[$c.Id] = New-Check $gP $c.Text 32 $yy 392 $true
    $yy += 23
}

# --- 3. Display and FPS cap ---
$gD = New-Group '3. Display and FPS cap' 450 8 430 190
$cbVrr = New-Check $gD 'G-Sync / FreeSync is ENABLED in the graphics driver' 15 22 405 $false
New-Label $gD 'Refresh rate (Hz):' 15 52 120 | Out-Null
$numHz = New-Num $gD 30 540 60 140 49 70
$cbFps = New-Check $gD 'Apply an FPS cap' 15 82 405 $true
New-Label $gD 'Cap mode:' 32 110 70 | Out-Null
$cbCapMode = New-Combo $gD @('Auto', 'Custom value', 'No limit') 105 107 130
$numCap = New-Num $gD 20 1000 144 245 107 70
$numCap.Enabled = $false
$lblCap = New-Label $gD '' 15 140 405 44

# --- 4. user.cfg ---
$gC = New-Group '4. user.cfg (game folder)' 450 202 430 128
$cbCfgCounter = New-Check $gC 'Show the FPS counter inside the game' 15 22
$cbCfgRal     = New-Check $gC 'Render queue: lowest input lag (2 frames on 4 threads or fewer)' 15 46
$cbCfgMisc    = New-Check $gC 'Triple buffering, V-Sync and motion blur off' 15 70
$cbCfgThreads = New-Check $gC 'BF6: CPU thread settings (cores / logical processors)' 15 46
$cbCfgExtra   = New-Check $gC 'BF6 extra: worker thread count (unverified)' 15 70 405 $false
$lblCfgNote   = New-Label $gC '' 15 98 405 22
$lblCfgNote.ForeColor = [Drawing.Color]::DimGray
$tt.SetToolTip($cbCfgExtra, "Adds Thread.MaxWorkerThreadCount <your thread count>.`r`nNo public source confirms that BF6 honours this line, so it is off by default.`r`nIf the game behaves worse, use Undo.")
$tt.SetToolTip($cbCfgCounter, "Writes PerfOverlay.DrawFps 1 (on-screen FPS counter).`r`nUnticked: nothing is written, unless your current user.cfg has the counter on;`r`nthen it is switched off (PerfOverlay.DrawFps 0).`r`nWorks in BF4, BF1 and BF V. Not confirmed for BF6: if the game ignores it, it is harmless.")
$tt.SetToolTip($cbCfgThreads, "Thread.ProcessorCount / MaxProcessorCount = physical cores,`r`nGstRender.Thread.MaxProcessorCount = logical processors.`r`nThe community fix for BF6's high CPU usage.")

# --- Buttons ---
$btnGen   = New-Btn 'Generate files (preview only)'                  450 342 430 38
$btnApply = New-Btn 'Generate and apply to the game (with backup)'   450 386 430 38
$btnUndo  = New-Btn 'Undo last apply (restore backups)'              450 430 430 38
$btnOpen  = New-Btn 'Open output folder'                             450 474 213 38
$btnReset = New-Btn 'Reset choices'                                  667 474 213 38
$lblNote  = New-Label $form 'Close the game before applying. Changing video options in-game later overwrites the profile values.' 450 520 430 36
$lblNote.ForeColor = [Drawing.Color]::DimGray
$lnk = New-Object Windows.Forms.LinkLabel
$lnk.Text = 'Project page, updates and help (GitHub)'
$lnk.Location = New-Object Drawing.Point(450, 558)
$lnk.Size = New-Object Drawing.Size(430, 20)
$form.Controls.Add($lnk)

# --- Log ---
$txtLog = New-Object Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object Drawing.Font('Consolas', 9)
$txtLog.Location = New-Object Drawing.Point(10, 584)
$txtLog.Size = New-Object Drawing.Size(870, 166)
$form.Controls.Add($txtLog)

# =============================================================================
#  LOGIC
# =============================================================================
$script:Ready = $false
$script:Hw = $null
$script:St = $null
$script:HzDetected = 60
$script:VrrDetected = $false
$script:LogLines = New-Object Collections.Generic.List[string]

function Write-Log([string]$t) {
    $script:LogLines.Add($t)
    $txtLog.AppendText($t + [Environment]::NewLine)
}

function Get-SelGame { $Games[[string]($cbGame.SelectedIndex + 1)] }

function Get-GpuTierInfo($g) {
    if ($g.Id -eq 'bf6') { Get-GpuTierBf6 $script:Hw.Gpu } else { Get-GpuTierClassic $script:Hw.Gpu }
}

function Get-EffTier {
    $g = Get-SelGame
    if ($cbTier.SelectedIndex -gt 0) { return [int]$cbTier.SelectedIndex }
    [int](Get-GpuTierInfo $g).Tier
}

function Get-EffCap {
    $g = Get-SelGame
    $hz = [int]$numHz.Value
    switch ($cbCapMode.SelectedIndex) {
        1 { return [pscustomobject]@{ Cap = [int]$numCap.Value; Why = 'custom value' } }
        2 { return [pscustomobject]@{ Cap = 0; Why = 'no limit' } }
    }
    $tier = Get-EffTier
    $classic = $g.Id -ne 'bf6'
    $strong = $tier -ge 3 -and $script:Hw.Threads -ge $(if ($classic) { 8 } else { 12 })
    if ($cbVrr.Checked) {
        $gap = [math]::Max(3, [int][math]::Ceiling($hz * $hz / 3600))
        return [pscustomobject]@{ Cap = $hz - $gap; Why = "VRR on: $gap FPS below $hz Hz keeps frames inside the G-Sync/FreeSync range" }
    }
    if ($script:Hw.IsLaptop -or -not $strong) {
        return [pscustomobject]@{ Cap = $hz; Why = 'no VRR: matches the refresh rate (stable frame times and temperatures)' }
    }
    if ($classic) {
        return [pscustomobject]@{ Cap = [math]::Min($hz * 2, 300); Why = 'no VRR, strong desktop: FPS above refresh lowers input latency' }
    }
    [pscustomobject]@{ Cap = 0; Why = 'no VRR, strong desktop: limiter off, FPS above refresh lowers input latency' }
}

# VRAM the tuning rules may use: BF6 trusts the registry value, BF V only when exact
function Get-VramFor($g) {
    $gpu = $script:Hw.Gpu
    switch ($g.Id) {
        'bf6'   { if ($gpu) { [double]$gpu.VramGB } else { 0 } }
        'bfv'   { if ($gpu -and $gpu.VramExact) { [double]$gpu.VramGB } else { 0 } }
        default { 0 }
    }
}

# Every PROFSAVE_profile setting the engine would write for this game and tier
function Get-AllSettings($g, [int]$tier) {
    $hw = $script:Hw
    $vramGB = Get-VramFor $g
    switch ($g.Id) {
        'bf4' { Get-ProfileSettingsBf4 $tier $hw.Threads }
        'bf1' { Get-ProfileSettingsBf1 $tier $hw.Threads }
        'bfv' { Get-ProfileSettingsBfv $tier $hw.Threads $vramGB }
        'bf6' { Get-ProfileSettingsBf6 $tier $hw.Threads $hw.Cores $vramGB $hw.IsLaptop }
    }
}

function Update-Ui {
    if (-not $script:Ready) { return }
    $g = Get-SelGame
    $classic = $g.Id -ne 'bf6'
    $ti = Get-GpuTierInfo $g
    $lblTier.Text = 'Detected: ' + @{ 1 = 'LOW'; 2 = 'MEDIUM'; 3 = 'HIGH' }[[int]$ti.Tier]
    $numCap.Enabled = ($cbCapMode.SelectedIndex -eq 1) -and $cbFps.Checked
    $cbCapMode.Enabled = $cbFps.Checked
    $cap = Get-EffCap
    $lblCap.Text = if ($cap.Cap -gt 0) { "Result: $($cap.Cap) FPS  ($($cap.Why))" } else { "Result: limiter off  ($($cap.Why))" }
    $cbCfgRal.Visible = $classic; $cbCfgMisc.Visible = $classic
    $cbCfgThreads.Visible = -not $classic; $cbCfgExtra.Visible = -not $classic
    $lblCfgNote.Text = if ($classic) { 'Your own lines in an existing user.cfg are kept.' } else { 'Optional. If BF6 behaves worse, use Undo.' }

    # Tweak groups: how many profile settings each one holds for this game and
    # tier (hover shows them); groups the game doesn't have are greyed out
    $all = Get-AllSettings $g (Get-EffTier)
    $keys = @{}
    foreach ($c in $Cats) { $keys[$c.Id] = New-Object Collections.Generic.List[string] }
    foreach ($k in $all.Keys) {
        if ($k -ne 'GstRender.OverallGraphicsQuality') { $keys[(Get-CatId $k)].Add(($k -replace '^GstRender\.', '')) }
    }
    foreach ($c in $Cats) {
        $cb = $script:cbCat[$c.Id]
        $n = $keys[$c.Id].Count
        $txt = if ($n -gt 0) { '{0} ({1})' -f $c.Text, $n } else { '{0} (n/a)' -f $c.Text }
        if ($cb.Text -ne $txt) { $cb.Text = $txt }
        $cb.Enabled = ($n -gt 0)
        $tip = if ($n -gt 0) { 'Settings: ' + ($keys[$c.Id] -join ', ') } else { "$($g.Name) has no settings in this group." }
        $tt.SetToolTip($cb, $tip)
    }
}

# The game rewrites PROFSAVE_profile when it exits, so it must be closed
# before the profile is read (and before the files are copied)
function Wait-GameClosedGui($g) {
    while (Test-GameRunning $g) {
        $r = [Windows.Forms.MessageBox]::Show("$($g.Name) is running.`r`n`r`nClose the game, then click OK. It rewrites its settings file when it closes.", 'Game running', 'OKCancel', 'Warning')
        if ($r -ne 'OK') { return $false }
    }
    $true
}

# "20261024_021500" (from a .bak_ file name) -> "2026-10-24 02:15"
function Get-BackupDate($file) {
    if (-not $file) { return '' }
    $s = $file.Name -replace '^.*\.bak_', ''
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($s, 'yyyyMMdd_HHmmss', $Invariant, [Globalization.DateTimeStyles]::None, [ref]$d)) {
        return $d.ToString('yyyy-MM-dd HH:mm')
    }
    $s
}

# -----------------------------------------------------------------------------
# Remember the choices between runs
# -----------------------------------------------------------------------------
function Export-GuiSettings {
    if (-not $script:Ready) { return }
    try {
        $cats = [ordered]@{}
        foreach ($c in $Cats) { $cats[$c.Id] = [bool]$script:cbCat[$c.Id].Checked }
        $s = [ordered]@{
            game       = (Get-SelGame).Id
            tier       = $cbTier.SelectedIndex
            profile    = $cbProfile.Checked
            cats       = $cats
            vrr        = $cbVrr.Checked
            fps        = $cbFps.Checked
            capMode    = $cbCapMode.SelectedIndex
            cap        = [int]$numCap.Value
            cfgCounter = $cbCfgCounter.Checked
            cfgRal     = $cbCfgRal.Checked
            cfgMisc    = $cbCfgMisc.Checked
            cfgThreads = $cbCfgThreads.Checked
            cfgExtra   = $cbCfgExtra.Checked
        }
        $dir = Split-Path -Parent $settingsFile
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        [IO.File]::WriteAllText($settingsFile, ($s | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    } catch { }
}

function Import-GuiSettings {
    try {
        if (-not (Test-Path -LiteralPath $settingsFile)) { return }
        $j = [IO.File]::ReadAllText($settingsFile) | ConvertFrom-Json
        if ($null -eq $j) { return }
        $i = 0
        foreach ($key in $Games.Keys) { if ($Games[$key].Id -eq $j.game) { $cbGame.SelectedIndex = $i }; $i++ }
        if ($null -ne $j.tier -and [int]$j.tier -ge 0 -and [int]$j.tier -lt $cbTier.Items.Count) { $cbTier.SelectedIndex = [int]$j.tier }
        if ($null -ne $j.capMode -and [int]$j.capMode -ge 0 -and [int]$j.capMode -lt $cbCapMode.Items.Count) { $cbCapMode.SelectedIndex = [int]$j.capMode }
        if ($null -ne $j.cap -and [int]$j.cap -ge 20 -and [int]$j.cap -le 1000) { $numCap.Value = [int]$j.cap }
        $map = @{ profile = $cbProfile; vrr = $cbVrr; fps = $cbFps; cfgCounter = $cbCfgCounter; cfgRal = $cbCfgRal
                  cfgMisc = $cbCfgMisc; cfgThreads = $cbCfgThreads; cfgExtra = $cbCfgExtra }
        foreach ($name in $map.Keys) {
            $v = $j.$name
            if ($null -ne $v) { $map[$name].Checked = [bool]$v }
        }
        if ($null -ne $j.cats) {
            foreach ($p in $j.cats.PSObject.Properties) {
                if ($script:cbCat.ContainsKey($p.Name)) { $script:cbCat[$p.Name].Checked = [bool]$p.Value }
            }
        }
    } catch { }
}

function Reset-Choices {
    $cbTier.SelectedIndex = 0
    $cbProfile.Checked = $true
    foreach ($c in $Cats) { $script:cbCat[$c.Id].Checked = $true }
    $cbVrr.Checked = $script:VrrDetected
    $numHz.Value = $script:HzDetected
    $cbFps.Checked = $true
    $cbCapMode.SelectedIndex = 0
    $numCap.Value = [math]::Max(20, [math]::Min($script:HzDetected, 1000))
    $cbCfgCounter.Checked = $true; $cbCfgRal.Checked = $true; $cbCfgMisc.Checked = $true
    $cbCfgThreads.Checked = $true; $cbCfgExtra.Checked = $false
    Update-Ui
}

# -----------------------------------------------------------------------------
# Generate: builds user.cfg and PROFSAVE_profile in <game>_Optimized
# -----------------------------------------------------------------------------
function Invoke-Generate {
    if (-not $script:Hw) { return $false }
    $g = Get-SelGame; $hw = $script:Hw; $id = $g.Id; $classic = $id -ne 'bf6'
    $txtLog.Clear(); $script:LogLines.Clear()

    $loc = Get-GameLocations $g $scriptDir
    $gameDir = $loc.GameDir; $profPath = $loc.ProfPath; $userCfgPath = $loc.UserCfgPath
    $profDir = if ($g.ProfileMode -eq 'fixed') { $loc.SettingsDir } elseif ($profPath) { Split-Path -Parent $profPath } else { $loc.SettingsDir }

    $outDir = Join-Path $scriptDir "$($g.Short)_Optimized"
    [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue)
    if (-not (Test-Write $outDir)) {
        $outDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "$($g.Short)_Optimized"
        [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop)
    }
    $outCfg  = Join-Path $outDir 'user.cfg'
    $outProf = Join-Path $outDir 'PROFSAVE_profile'
    foreach ($f in $outCfg, $outProf) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

    $tier = Get-EffTier
    $capI = Get-EffCap; $cap = $capI.Cap
    $tierTxt = @{ 1 = 'LOW'; 2 = 'MEDIUM'; 3 = 'HIGH' }[$tier]
    $ti = Get-GpuTierInfo $g

    Write-Log "=== $($g.Name) - $(Get-Date -Format 'yyyy-MM-dd HH:mm') (GUI v$GuiVersion, engine v$AppVersion) ==="
    Write-Log ("GPU: {0} | tier used: {1}{2}" -f $hw.Gpu.Name, $tierTxt, $(if ($cbTier.SelectedIndex -eq 0) { " (auto, from $($ti.Source))" } else { ' (chosen by you)' }))
    Write-Log ("Game folder: {0}" -f $(if ($gameDir) { $gameDir } else { 'NOT detected' }))
    foreach ($w in Get-HwWarnings $g $hw $hw.Hz) { Write-Log "WARNING: $w" }
    if (Test-GameRunning $g) {
        Write-Log "NOTE: $($g.Name) is running. It saves its settings when it closes, so the profile below may be outdated. 'Generate and apply' asks you to close the game first."
    }
    Write-Log ''

    # ---- user.cfg ----
    $cfg = @()
    $fpsLine = Get-FpsCounterCfg $userCfgPath $cbCfgCounter.Checked
    if ($fpsLine) { $cfg += $fpsLine }
    if ($classic) {
        $ral = if ($hw.Threads -le 4) { 2 } else { 1 }
        # "No limit" is written as a high number instead of 0, whose meaning is not documented
        $cfgCap = if ($cap -gt 0) { $cap } else { 999 }
        if ($cbFps.Checked)        { $cfg += "GameTime.MaxVariableFps $cfgCap" }
        if ($cbCfgRal.Checked)     { $cfg += "RenderDevice.RenderAheadLimit $ral" }
        if ($cbCfgMisc.Checked)    { $cfg += 'RenderDevice.TripleBufferingEnable 0', 'RenderDevice.VSyncEnable 0', 'WorldRender.MotionBlurEnable 0' }
    } else {
        if ($cbCfgThreads.Checked -and $hw.Cores -and $hw.Threads) {
            $cfg += @("Thread.ProcessorCount $($hw.Cores)", "Thread.MaxProcessorCount $($hw.Cores)",
                     'Thread.MinFreeProcessorCount 0', 'Thread.JobThreadPriority 0',
                     "GstRender.Thread.MaxProcessorCount $($hw.Threads)")
        }
        if ($cbCfgExtra.Checked -and $hw.Threads) { $cfg += Get-Bf6ExtraCfg $hw.Threads }
    }
    $haveCfg = $cfg.Count -gt 0
    Write-Log '--- user.cfg ---'
    if ($haveCfg) {
        $kept = Build-UserCfg $userCfgPath $cfg $outCfg
        $cfg | ForEach-Object { Write-Log "  $_" }
        if ($kept) { Write-Log ("Kept {0} line(s) from your existing user.cfg." -f $kept) }
        if ($fpsLine -eq 'PerfOverlay.DrawFps 0') { Write-Log 'FPS counter: switched off (your existing user.cfg had it on).' }
        if (-not $classic -and $cbCfgCounter.Checked) { Write-Log 'FPS counter: not confirmed for BF6; if no counter appears, the game ignores it (harmless).' }
        if ($classic -and $cbFps.Checked) {
            Write-Log $(if ($cap -gt 0) { "FPS cap: $cap -> $($capI.Why)" } else { "FPS cap: none (written as 999) -> $($capI.Why)" })
        }
        if (-not $classic -and $cbCfgExtra.Checked) { Write-Log 'Extras are experimental: if BF6 behaves worse, use Undo.' }
    } else {
        Write-Log 'Nothing selected: no user.cfg generated.'
    }

    # ---- PROFSAVE_profile ----
    Write-Log ''
    Write-Log '--- PROFSAVE_profile ---'
    $haveProf = $false
    $nChanges = -1
    if ($cbProfile.Checked) {
        $settings = Select-Settings (Get-AllSettings $g $tier)
        if (-not $classic -and $cbFps.Checked) {
            if ($cap -gt 0) {
                $settings['GstRender.FrameRateLimiterEnable'] = '1'
                $settings['GstRender.FrameRateLimit'] = ([double]$cap).ToString('F6', $Invariant)
            } else {
                $settings['GstRender.FrameRateLimiterEnable'] = '0'
            }
            Write-Log $(if ($cap -gt 0) { "FPS limiter: $cap -> $($capI.Why)" } else { "FPS limiter: off -> $($capI.Why)" })
        }
        $canBuild = [bool]$profPath -and (-not $g.NeedProfile -or (Test-Path -LiteralPath $profPath))
        if ($settings.Count -eq 0) {
            Write-Log 'No tweaks ticked: no profile generated.'
        } elseif ($canBuild) {
            $res = Build-Profile $profPath $settings $outProf $g.Eol
            $haveProf = $true
            if ($res.FromExisting) {
                $nChanges = $res.Changes.Count + $res.Added.Count
                Write-Log 'Based on your current profile: keybinds, mouse, FOV, HUD, audio and resolution are preserved.'
                if ($res.Changes.Count) { Write-Log 'Changes:'; $res.Changes | ForEach-Object { Write-Log "  $_" } }
                if ($res.Added.Count)   { Write-Log 'Added:';   $res.Added   | ForEach-Object { Write-Log "  $_" } }
                if (-not $res.Changes.Count -and -not $res.Added.Count) { Write-Log 'Your profile already has these values; the generated file is identical.' }

                # Same hints as the script
                $fr = $res.Lines | Where-Object { $_ -match '^GstRender\.FullscreenRefreshRate\s' } | Select-Object -First 1
                $frHz = if ($fr -match '([\d.]+)\s*$') { $Matches[1] -as [double] } else { $null }
                $hzNow = [int]$numHz.Value
                if ($frHz -gt 0 -and $frHz -lt ($hzNow - 1)) {
                    $where = if ($id -eq 'bf6') { "the game's display settings" } else { 'Options > Video' }
                    Write-Log ("WARNING: the game is set to {0:N0} Hz but the display supports {1} Hz. Select {1} Hz in {2}." -f $frHz, $hzNow, $where)
                }
                if ($id -eq 'bfv' -and ($res.Lines | Where-Object { $_ -match '^GstRender\.Dx12Enabled\s+1' })) {
                    Write-Log 'DirectX 12 is on (needed for DXR and DLSS). If you get stutter, try DX11 in Options > Video.'
                }
                if ($id -eq 'bf6' -and $tier -eq 1) { Write-Log 'Tip: on this GPU, turn on DLSS / FSR / XeSS (Quality) in Options > Graphics for a big FPS gain.' }
                if ($id -eq 'bf1' -and $script:cbCat['dx'].Checked) { Write-Log 'Note: the profile switches BF1 to DirectX 11 (more stable frame times than DX12).' }
            } else {
                Write-Log "No $($g.Short) profile on this PC: a graphics-only profile was created (other options use game defaults)."
            }
        } else {
            Write-Log "No $($g.Short) settings file found. Start the game once, close it and generate again."
        }
    } else {
        Write-Log 'Skipped (unticked).'
    }

    Write-Log ''
    Write-Log "--- Graphics driver settings for $($g.Exe) ---"
    foreach ($l in Get-DriverAdvice $g $hw.Gpu $cbVrr.Checked) { Write-Log $l }

    Write-Log ''
    Write-Log "Files saved in: $outDir"
    try { [IO.File]::WriteAllLines((Join-Path $outDir 'README.txt'), $script:LogLines.ToArray(), (New-Object Text.UTF8Encoding $true)) } catch { }

    $script:St = [pscustomobject]@{
        G = $g; OutDir = $outDir; OutCfg = $outCfg; OutProf = $outProf
        HaveCfg = $haveCfg; HaveProf = $haveProf; NChanges = $nChanges
        ProfPath = $profPath; ProfDir = $profDir; UserCfgPath = $userCfgPath; GameDir = $gameDir
    }
    Export-GuiSettings
    # Show the top of the report (what changes) rather than the driver notes at the end
    $txtLog.SelectionStart = 0; $txtLog.SelectionLength = 0; $txtLog.ScrollToCaret()
    $true
}

function Invoke-Apply {
    $st = $script:St; $g = $st.G
    if (-not ($st.HaveCfg -or $st.HaveProf)) {
        [void][Windows.Forms.MessageBox]::Show('There is nothing to apply. Tick at least one option.', 'Nothing to apply', 'OK', 'Information')
        return
    }
    $targets = @()
    if ($st.HaveProf) {
        $sum = if ($st.NChanges -lt 0) { 'new graphics-only profile' } elseif ($st.NChanges -eq 0) { 'already optimized' } else { "$($st.NChanges) setting(s) change" }
        $targets += "PROFSAVE_profile ($sum) -> $($st.ProfPath)"
    }
    if ($st.HaveCfg)  { $targets += "user.cfg -> $(if ($st.GameDir) { $st.GameDir } else { '(game folder not detected, will be skipped)' })" }
    $q = "Copy these files now? Backups are made first.`r`n`r`n" + ($targets -join "`r`n")
    if ([Windows.Forms.MessageBox]::Show($q, "Apply to $($g.Name)", 'YesNo', 'Question') -ne 'Yes') {
        Write-Log ''; Write-Log 'Nothing was changed.'; return
    }
    if (-not (Wait-GameClosedGui $g)) { Write-Log ''; Write-Log 'Cancelled: the game is still running.'; return }

    $stamp = Get-Date -Format yyyyMMdd_HHmmss
    Write-Log ''
    if ($st.HaveProf) {
        if (-not $g.NeedProfile) { [void](New-Item -ItemType Directory -Path $st.ProfDir -Force -ErrorAction SilentlyContinue) }
        if ((Install-File $st.OutProf $st.ProfPath $stamp) -eq 'ok') { Write-Log "PROFSAVE_profile applied (backup: PROFSAVE_profile.bak_$stamp)" }
        else { Write-Log "ERROR: PROFSAVE_profile could not be applied. Copy it manually to $(Split-Path -Parent $st.ProfPath)" }
    }
    if ($st.HaveCfg) {
        if (-not $st.GameDir) { Write-Log 'user.cfg: game folder not detected. Copy it manually.' }
        else {
            switch (Install-File $st.OutCfg $st.UserCfgPath $stamp) {
                'ok'     { Write-Log "user.cfg applied to $($st.GameDir) (backup: user.cfg.bak_$stamp)" }
                'denied' { Write-Log 'user.cfg: administrator permission declined. Copy it manually.' }
                default  { Write-Log 'ERROR: user.cfg could not be applied (antivirus or Controlled Folder Access may block the game folder).' }
            }
        }
    }
    Write-Log 'Done. Use "Undo last apply" to go back.'
}

function Invoke-UndoGui {
    $g = Get-SelGame
    $loc = Get-GameLocations $g $scriptDir
    $txtLog.Clear(); $script:LogLines.Clear()
    $bp = Get-LatestBackup $loc.ProfPath
    $bc = Get-LatestBackup $loc.UserCfgPath
    if (-not $bp -and -not $bc) {
        Write-Log "No backups found for $($g.Name)."; return
    }
    $what = @()
    foreach ($item in @(@('PROFSAVE_profile', $bp), @('user.cfg', $bc))) {
        $bak = $item[1]
        if (-not $bak) { continue }
        $note = if ($bak.Length -eq 0) { 'it did not exist before, so it will be removed' } else { 'backup from ' + (Get-BackupDate $bak) }
        $what += ('{0}: {1}' -f $item[0], $note)
    }
    $q = "Restore the previous files for $($g.Name)?`r`n`r`n" + ($what -join "`r`n")
    if ([Windows.Forms.MessageBox]::Show($q, 'Undo', 'YesNo', 'Question') -ne 'Yes') { return }
    if (-not (Wait-GameClosedGui $g)) { Write-Log 'Cancelled: the game is still running.'; return }
    foreach ($f in @($loc.ProfPath, $loc.UserCfgPath)) {
        if (-not $f) { continue }
        $name = Split-Path -Leaf $f
        switch (Restore-File $f) {
            'restored' { Write-Log "$name restored from backup." }
            'removed'  { Write-Log "$name removed (it did not exist before the optimizer)." }
            'none'     { Write-Log "$name has no backup; left unchanged." }
            'denied'   { Write-Log "$name not restored: administrator permission was declined." }
            default    { Write-Log "$name could not be restored. The .bak_ files are in $(Split-Path -Parent $f)" }
        }
    }
}

# =============================================================================
#  EVENTS
# =============================================================================
function Invoke-Safe([scriptblock]$sb) {
    $form.Cursor = 'WaitCursor'
    try { & $sb } catch { Show-Error ("Unexpected error: {0}`r`nLine {1}" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber) }
    finally { $form.Cursor = 'Default' }
}

foreach ($c in @($cbTier, $cbCapMode, $cbVrr, $cbFps, $numHz, $numCap)) {
    if ($c -is [Windows.Forms.NumericUpDown]) { $c.Add_ValueChanged({ Update-Ui }) }
    elseif ($c -is [Windows.Forms.CheckBox])  { $c.Add_CheckedChanged({ Update-Ui }) }
    else                                      { $c.Add_SelectedIndexChanged({ Update-Ui }) }
}
$cbGame.Add_SelectedIndexChanged({ Update-Ui })

$btnGen.Add_Click({   Invoke-Safe { [void](Invoke-Generate) } })
$btnApply.Add_Click({
    Invoke-Safe {
        $g = Get-SelGame
        # Close the game BEFORE the files are generated: it saves its profile on exit,
        # and a file built from the old copy would overwrite that session's changes
        if (-not (Wait-GameClosedGui $g)) {
            $txtLog.Clear(); $script:LogLines.Clear()
            Write-Log 'Cancelled: the game is still running.'
            return
        }
        if (Invoke-Generate) { Invoke-Apply }
    }
})
$btnUndo.Add_Click({  Invoke-Safe { Invoke-UndoGui } })
$btnReset.Add_Click({ Invoke-Safe { Reset-Choices } })
$btnOpen.Add_Click({
    $d = if ($script:St) { $script:St.OutDir } else { $scriptDir }
    Start-Process explorer.exe -ArgumentList "`"$d`""
})
$lnk.Add_LinkClicked({ Start-Process $RepoUrl })
$form.Add_FormClosing({ Export-GuiSettings })

$form.Add_Shown({
    Invoke-Safe {
        $lblHw.Text = 'Detecting hardware... (a few seconds)'
        $form.Refresh()
        $script:Hw = Get-Hardware
        $hw = $script:Hw

        $lines = @()
        $lines += "CPU: $($hw.CpuName)  ($($hw.Cores) cores / $($hw.Threads) threads)"
        $lines += "RAM: $($hw.RamGB) GB"
        if ($hw.Gpu) { $lines += ("GPU: {0}  ({1}{2} GB VRAM)" -f $hw.Gpu.Name, $hw.Gpu.VramGB, $(if ($hw.Gpu.VramExact) { '' } else { '+' })) }
        else { $lines += 'GPU: not detected (Low preset will be used)' }
        $lines += "System: $(if ($hw.IsLaptop) { 'Laptop' } else { 'Desktop' })"
        $lines += "Display: $($hw.Hz) Hz (current Windows refresh rate)"
        foreach ($m in $hw.Mons) {
            $tags = @()
            if ($m.FreeSync) { $tags += 'FreeSync' }
            if ($m.HdmiVrr) { $tags += 'HDMI VRR' }
            if ($m.DpAdaptiveSync) { $tags += 'DP Adaptive-Sync' }
            if ($m.RangeVrr) { $tags += 'VRR range (hint)' }
            if ($m.NvidiaVsdb) { $tags += 'G-Sync (hint)' }
            $lines += ("Monitor: {0} | {1}" -f $m.Name, $(if ($tags) { $tags -join ', ' } else { 'no VRR advertised' }))
        }
        $lblHw.Text = $lines -join "`r`n"

        $hz = [int]$hw.Hz; if ($hz -lt 30) { $hz = 60 }
        $script:HzDetected = [math]::Min($hz, 540)
        $script:VrrDetected = [bool]($hw.Mons | Where-Object { $_.FreeSync -or $_.HdmiVrr -or $_.DpAdaptiveSync -or $_.RangeVrr -or $_.NvidiaVsdb })
        $numHz.Value = $script:HzDetected
        $numCap.Value = [math]::Max(20, [math]::Min($hz, 1000))
        $cbVrr.Checked = $script:VrrDetected

        $cbGame.Items.Clear()
        foreach ($key in $Games.Keys) {
            $g = $Games[$key]
            $loc = Get-GameLocations $g $scriptDir
            $hasProf = $loc.ProfPath -and (Test-Path -LiteralPath $loc.ProfPath)
            $status = if ($loc.GameDir -and $hasProf) { 'installed, settings found' }
                      elseif ($loc.GameDir) { 'installed' }
                      elseif ($hasProf) { 'settings found' }
                      else { 'not detected' }
            [void]$cbGame.Items.Add(("{0}  [{1}]" -f $g.Name, $status))
        }
        $cbGame.SelectedIndex = 0
        Import-GuiSettings          # last session's choices (the window opens on the same game)
        $script:Ready = $true
        Update-Ui
        Write-Log 'Choose your options and click "Generate files" to preview, or "Generate and apply".'
    }
})

[void]$form.ShowDialog()

} catch {
    Show-Error ("Could not start: {0}`r`nLine {1}" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
}
