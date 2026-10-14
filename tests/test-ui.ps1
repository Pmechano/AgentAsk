# Exercise the production WPF event handlers with three independent requests.
param([string]$OutputRoot = $env:TEMP)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ui\ask-window.ps1')
$OutputRoot = Join-Path $OutputRoot ('AgentAsk-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($OutputRoot)
$windows = @()
$configPath = Join-Path $OutputRoot 'config.json'
function Update-WpfEvents {
    $frame = New-Object Windows.Threading.DispatcherFrame
    $stop = { $frame.Continue = $false }.GetNewClosure()
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [Windows.Threading.DispatcherPriority]::Background, [Action]$stop)
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Invoke-TestClick {
    param($Button)
    $Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
}
try {
    foreach ($index in 0..2) {
        $id = [Guid]::NewGuid().ToString('N')
        $request = [pscustomobject]@{
            config_path = $configPath
            request_id = $id; agent = "smoke-test-$index"; title = 'AgentAsk automatic test'
            question = (("Automatic test $index - closes by itself.`n") * 30)
        }
        $window = New-AgentAskWindow $request (Join-Path $OutputRoot "$index.json")
        $windows += $window
        $window.Show()
    }
    Update-WpfEvents
    if (@($windows | Where-Object IsVisible).Count -ne 3) { throw 'Expected three independent visible windows' }
    $expected = ([string][char]0x4F60) + ([string][char]0x597D) + "`r`nanswer `$()"
    $windows[0].FindName('Answer').Text = $expected
    Update-WpfEvents
    if ($windows[0].FindName('Placeholder').Visibility -ne 'Collapsed') { throw 'Placeholder covers the answer' }
    Invoke-TestClick $windows[0].FindName('Settings')
    Update-WpfEvents
    if (-not $windows[0].FindName('SettingsPopup').IsOpen) { throw 'Settings did not open' }
    $windows[0].FindName('MotionToggle').IsChecked = $false
    Invoke-TestClick $windows[0].FindName('SaveSettings')
    if ($windows[0].FindName('SettingsError').Text) { throw $windows[0].FindName('SettingsError').Text }
    if ($windows[0].FindName('EdgeLight').HasAnimatedProperties) { throw 'Motion did not stop' }
    Invoke-TestClick $windows[0].FindName('Settings')
    $windows[0].FindName('MotionToggle').IsChecked = $true
    Invoke-TestClick $windows[0].FindName('SaveSettings')
    if ($windows[0].FindName('SettingsError').Text) { throw $windows[0].FindName('SettingsError').Text }
    if (-not $windows[0].FindName('EdgeLight').HasAnimatedProperties) { throw 'Motion did not restart' }
    Invoke-TestClick $windows[0].FindName('Settings')
    Update-WpfEvents
    $motion = $windows[0].FindName('MotionToggle')
    $source = [Windows.PresentationSource]::FromVisual($motion)
    $escape = [Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,
        $source, 0, [Windows.Input.Key]::Escape)
    $escape.RoutedEvent = [Windows.Input.Keyboard]::PreviewKeyDownEvent
    $motion.RaiseEvent($escape)
    if ($windows[0].FindName('SettingsPopup').IsOpen -or -not $windows[0].IsVisible) {
        throw 'Escape should close settings without cancelling the question'
    }
    if ($windows[0].FindName('Answer').Text -cne $expected) { throw 'Settings lost the draft' }
    $question = $windows[0].FindName('Question')
    $question.ScrollToEnd()
    Update-WpfEvents
    if ($question.VerticalOffset -le 0) { throw 'Long question did not scroll' }
    Invoke-TestClick $windows[0].FindName('Submit')
    Invoke-TestClick $windows[1].FindName('Cancel')
    $windows[2].Close()
    Update-WpfEvents
    if ($windows[0].FindName('EdgeLight').HasAnimatedProperties) { throw 'Animation survived window close' }
    $responses = @(0..2 | ForEach-Object {
        [IO.File]::ReadAllText((Join-Path $OutputRoot "$_.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
    })
    if ($responses[0].status -ne 'answered' -or $responses[0].answer -cne $expected) { throw 'Answer roundtrip failed' }
    if ($responses[1].status -ne 'cancelled' -or $responses[2].status -ne 'cancelled') { throw 'Cancellation failed' }
    if (@($responses.request_id | Select-Object -Unique).Count -ne 3) { throw 'Request isolation failed' }
    Write-Output 'PASS: concurrent WPF windows, Unicode answer, scroll, motion toggle, draft preservation, submit/cancel/close.'
}
finally {
    foreach ($window in $windows) { if ($window.IsVisible) { $window.Close() } }
    if (Test-Path $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
}
