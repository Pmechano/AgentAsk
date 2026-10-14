# Persistent settings shared by independent Windows processes.
$script:AgentAskDefaultsPath = Join-Path $PSScriptRoot '..\config.defaults.json'

function Read-AgentAskConfig {
    param([string]$Path)
    $result = [IO.File]::ReadAllText($script:AgentAskDefaultsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([IO.File]::Exists($Path)) {
        $overrides = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($null -eq $overrides -or $overrides -isnot [pscustomobject]) { throw 'Config must be a JSON object.' }
        foreach ($section in $overrides.PSObject.Properties) {
            if ($section.Name -notin @('appearance', 'behavior') -or $section.Value -isnot [pscustomobject]) {
                throw "Invalid config section: $($section.Name)"
            }
            foreach ($item in $section.Value.PSObject.Properties) {
                if ($item.Name -notin @($result.($section.Name).PSObject.Properties.Name)) {
                    throw "Unknown setting: $($section.Name).$($item.Name)"
                }
                $result.($section.Name).($item.Name) = $item.Value
            }
        }
    }
    Test-AgentAskConfig $result
    return $result
}

function Test-AgentAskConfig {
    param($Config)
    foreach ($pair in @('appearance.edge_animation', 'behavior.enabled', 'behavior.topmost', 'behavior.timeout_enabled')) {
        $parts = $pair.Split('.')
        if ($Config.($parts[0]).($parts[1]) -isnot [bool]) { throw "$pair must be true or false." }
    }
    foreach ($rule in @(
        @('appearance', 'window_scale', 0.7, 1.5, $false),
        @('appearance', 'font_size', 12, 28, $true),
        @('behavior', 'timeout_seconds', 1, 86400, $true)
    )) {
        $value = $Config.($rule[0]).($rule[1])
        if ($value -isnot [ValueType] -or $value -is [bool] -or
            [double]::IsNaN($value) -or [double]::IsInfinity($value) -or
            $value -lt $rule[2] -or $value -gt $rule[3] -or
            ($rule[4] -and [Math]::Floor($value) -ne $value)) {
            throw "Invalid $($rule[0]).$($rule[1]); range $($rule[2]) to $($rule[3])."
        }
    }
}

function Save-AgentAskConfig {
    param([string]$Path, $Before, $After)
    Test-AgentAskConfig $After
    $fullPath = [IO.Path]::GetFullPath($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fullPath.ToUpperInvariant()))).Replace('-', '') }
    finally { $sha.Dispose() }
    $mutex = [Threading.Mutex]::new($false, ('Local\AgentAsk-Config-' + $hash))
    $locked = $false
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($fullPath)) ('.config.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        try { $locked = $mutex.WaitOne(3000) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Settings are being saved by another window. Please retry.' }
        $latest = Read-AgentAskConfig $fullPath
        $wasDisabled = -not $latest.behavior.enabled
        foreach ($section in @('appearance', 'behavior')) {
            foreach ($item in $After.$section.PSObject.Properties) {
                # Merge only edits made in this panel; do not overwrite other windows' changes.
                if ($item.Value -cne $Before.$section.($item.Name)) {
                    $latest.$section.($item.Name) = $item.Value
                }
            }
        }
        # A stale panel cannot re-enable a globally disabled tool.
        if ($wasDisabled) { $latest.behavior.enabled = $false }
        Test-AgentAskConfig $latest
        [IO.File]::WriteAllText($temporary, ($latest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($fullPath)) { [IO.File]::Replace($temporary, $fullPath, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $fullPath) }
        return $latest
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Apply-AgentAskConfig {
    param($Window, $Config, [switch]$Initial)
    $state = $Window.Tag
    $previous = $state.Config
    $state.Config = $Config
    $work = [Windows.SystemParameters]::WorkArea
    $scale = [Math]::Min($Config.appearance.window_scale,
        [Math]::Min(($work.Width - 24) / 936, ($work.Height - 24) / 650))
    $centerX = $Window.Left + $Window.Width / 2
    $centerY = $Window.Top + $Window.Height / 2
    $Window.Width = 936 * $scale
    $Window.Height = 650 * $scale
    if ($Initial) {
        $offset = ([Convert]::ToInt32($state.Request.request_id.Substring(0, 2), 16) % 5 - 2) * 16
        $centerX = $work.Left + $work.Width / 2 + $offset
        $centerY = $work.Top + $work.Height / 2 + $offset
    }
    $Window.Left = [Math]::Max($work.Left, [Math]::Min($work.Right - $Window.Width, $centerX - $Window.Width / 2))
    $Window.Top = [Math]::Max($work.Top, [Math]::Min($work.Bottom - $Window.Height, $centerY - $Window.Height / 2))
    $Window.FindName('Answer').FontSize = $Config.appearance.font_size
    $Window.FindName('Question').FontSize = $Config.appearance.font_size + 4
    $Window.FindName('Placeholder').FontSize = $Config.appearance.font_size
    $Window.Topmost = $Config.behavior.topmost
    Set-AgentAskMotion $Window ($Config.appearance.edge_animation -and [Windows.SystemParameters]::ClientAreaAnimation)
    if ($null -eq $previous -or
        $previous.behavior.timeout_enabled -ne $Config.behavior.timeout_enabled -or
        $previous.behavior.timeout_seconds -ne $Config.behavior.timeout_seconds) {
        $state.Clock.Restart()
    }
}

function Open-AgentAskSettings {
    param($Window)
    $config = Read-AgentAskConfig $Window.Tag.ConfigPath
    $Window.Tag.EditSnapshot = $config
    $Window.FindName('WindowScale').Value = $config.appearance.window_scale * 100
    $Window.FindName('FontSize').Value = $config.appearance.font_size
    $Window.FindName('MotionToggle').IsChecked = $config.appearance.edge_animation
    $Window.FindName('EnabledToggle').IsChecked = $config.behavior.enabled
    $Window.FindName('TopmostToggle').IsChecked = $config.behavior.topmost
    $Window.FindName('TimeoutToggle').IsChecked = $config.behavior.timeout_enabled
    $Window.FindName('TimeoutSeconds').Text = [string]$config.behavior.timeout_seconds
    $Window.FindName('SettingsError').Text = ''
    $Window.FindName('SettingsPopup').IsOpen = $true
}

function Update-AgentAskLifecycle {
    param($Window)
    $state = $Window.Tag
    if ($state.Saved) { return }
    $stamp = [IO.File]::GetLastWriteTimeUtc($state.ConfigPath).Ticks
    if ($stamp -ne $state.ConfigStamp) {
        $state.ConfigStamp = $stamp
        try {
            $latest = Read-AgentAskConfig $state.ConfigPath
            if (-not $latest.behavior.enabled) {
                Save-AgentAskResponse $state 'disabled' $null
                $Window.Close()
                return
            }
        }
        catch { [Console]::Error.WriteLine($_.Exception.Message) }
    }
    if ($state.Config.behavior.timeout_enabled) {
        $remaining = [Math]::Max(0, [Math]::Ceiling($state.Config.behavior.timeout_seconds - $state.Clock.Elapsed.TotalSeconds))
        $Window.FindName('Countdown').Text = $remaining.ToString() + ' s'
        $Window.FindName('Countdown').Visibility = 'Visible'
        if ($state.Clock.Elapsed.TotalSeconds -ge $state.Config.behavior.timeout_seconds) {
            # A generated sentinel is never recorded as a user-authored answer.
            $answer = '[' + [char]0x65E0 + [char]0x56DE + [char]0x7B54 + ']'
            try {
                Save-AgentAskResponse $state 'timed_out' $answer
                $Window.Close()
            }
            catch {
                $state.Timer.Stop()
                [void][Windows.MessageBox]::Show($Window, $_.Exception.Message, 'Could not save timeout', 'OK', 'Error')
            }
        }
    }
    else { $Window.FindName('Countdown').Visibility = 'Collapsed' }
}
