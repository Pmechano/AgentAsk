# Uses isolated files only. No user preferences are read or modified.
param([string]$OutputRoot = $env:TEMP)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ui\ask-window.ps1')
$root = Join-Path $OutputRoot ('AgentAsk-settings-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$configPath = Join-Path $root 'config.json'
$windows = @()
function Copy-Config($Value) { return ($Value | ConvertTo-Json -Depth 8 | ConvertFrom-Json) }
function Pump-Events {
    $frame = New-Object Windows.Threading.DispatcherFrame
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [Windows.Threading.DispatcherPriority]::Background, [Action]{ $frame.Continue = $false })
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Test-Window([string]$Name) {
    $request = [pscustomobject]@{
        request_id = [Guid]::NewGuid().ToString('N'); agent = $Name
        title = 'AgentAsk configuration test'; question = 'Automatic test; closes by itself.'
        config_path = $configPath
    }
    return (New-AgentAskWindow $request (Join-Path $root ($Name + '.json')))
}
try {
    $baseline = Read-AgentAskConfig $configPath
    $first = Copy-Config $baseline
    $second = Copy-Config $baseline
    $first.appearance.font_size = 22
    $second.behavior.topmost = $true
    [void](Save-AgentAskConfig $configPath $baseline $first)
    $merged = Save-AgentAskConfig $configPath $baseline $second
    if ($merged.appearance.font_size -ne 22 -or -not $merged.behavior.topmost) { throw 'Stale panel overwrote another setting' }
    $invalid = Copy-Config $merged
    $invalid.behavior.timeout_seconds = 0
    $rejected = $false
    try { [void](Save-AgentAskConfig $configPath $merged $invalid) }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid timeout accepted' }
    if ((Read-AgentAskConfig $configPath).behavior.timeout_seconds -ne 120) { throw 'Invalid save changed the file' }

    $timeout = Copy-Config $merged
    $timeout.appearance.window_scale = 0.8
    $timeout.appearance.edge_animation = $false
    $timeout.behavior.timeout_enabled = $true
    $timeout.behavior.timeout_seconds = 1
    [void](Save-AgentAskConfig $configPath $merged $timeout)
    $waiter = Test-Window 'timeout'
    $submitted = Test-Window 'submitted'
    $cancelled = Test-Window 'cancelled'
    $windows += @($waiter, $submitted, $cancelled)
    foreach ($window in $windows) { $window.Show() }
    Pump-Events
    if (-not $waiter.Topmost -or $waiter.FindName('Answer').FontSize -ne 22 -or $waiter.Width -gt 750) {
        throw 'Appearance/topmost settings were not applied'
    }
    if ($waiter.FindName('EdgeLight').HasAnimatedProperties) { throw 'Disabled motion still runs' }
    $submitted.FindName('Answer').Text = 'submitted before timeout'
    $submitted.FindName('Submit').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $cancelled.FindName('Cancel').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $deadline = [DateTime]::UtcNow.AddSeconds(6)
    while ($waiter.IsVisible -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 30
        Pump-Events
    }
    if ($waiter.IsVisible) { throw 'Timed-out window did not close' }
    $response = [IO.File]::ReadAllText((Join-Path $root 'timeout.json')) | ConvertFrom-Json
    $sentinel = '[' + [char]0x65E0 + [char]0x56DE + [char]0x7B54 + ']'
    if ($response.status -ne 'timed_out' -or $response.answer -cne $sentinel) { throw 'Wrong timeout response' }
    $response = [IO.File]::ReadAllText((Join-Path $root 'submitted.json')) | ConvertFrom-Json
    if ($response.status -ne 'answered' -or $response.answer -ne 'submitted before timeout') { throw 'Timeout overwrote submission' }
    $response = [IO.File]::ReadAllText((Join-Path $root 'cancelled.json')) | ConvertFrom-Json
    if ($response.status -ne 'cancelled') { throw 'Timeout overwrote cancellation' }
    foreach ($window in $windows) { if ($window.Tag.Timer.IsEnabled) { throw 'Timer survived closed window' } }

    $noTimeout = Copy-Config $timeout
    $noTimeout.behavior.timeout_enabled = $false
    [void](Save-AgentAskConfig $configPath $timeout $noTimeout)
    $open = Test-Window 'disabled-open'
    $observer = Test-Window 'disabled-observer'
    $windows += @($open, $observer)
    $open.Show()
    $observer.Show()
    Pump-Events
    Open-AgentAskSettings $open
    $open.FindName('EnabledToggle').IsChecked = $false
    $open.FindName('SaveSettings').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if ($open.FindName('SettingsError').Text) { throw $open.FindName('SettingsError').Text }
    if ($open.IsVisible) { throw 'Disabling did not close current window' }
    if ((Read-AgentAskConfig $configPath).behavior.enabled) { throw 'Disable was not persisted' }
    $disabledConfig = Read-AgentAskConfig $configPath
    $attempt = Copy-Config $disabledConfig
    $attempt.behavior.enabled = $true
    if ((Save-AgentAskConfig $configPath $disabledConfig $attempt).behavior.enabled) {
        throw 'Stale panel re-enabled AgentAsk without a manual config edit'
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ($observer.IsVisible -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 30
        Pump-Events
    }
    if ($observer.IsVisible) { throw 'Another waiting window did not observe disable' }
    $blocked = Test-Window 'disabled-new'
    if (-not $blocked.Tag.Saved -or $blocked.IsVisible) { throw 'Disabled request was not skipped' }
    $response = [IO.File]::ReadAllText((Join-Path $root 'disabled-new.json')) | ConvertFrom-Json
    if ($response.status -ne 'disabled' -or $null -ne $response.answer) { throw 'Invalid disabled result' }
    Write-Output 'PASS: persistent settings, stale-save merge, validation, sizing/fonts/topmost, timeout, submit/cancel races, disable.'
}
finally {
    foreach ($window in $windows) { if ($window.IsVisible) { $window.Close() } }
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
