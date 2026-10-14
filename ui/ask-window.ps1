param([string]$RequestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
$script:AgentAskUiRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'settings.ps1')

function Save-AgentAskResponse {
    param($State, [string]$Status, $Answer, $ErrorMessage = $null)
    if ($State.Saved) { return }
    $response = [ordered]@{
        schema_version = 1
        request_id = $State.Request.request_id
        agent = $State.Request.agent
        status = $Status
        answer = $Answer
        answered_at = [DateTime]::UtcNow.ToString('o')
    }
    if ($null -ne $ErrorMessage) { $response.error = $ErrorMessage }
    $temporary = $State.ResponsePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($response | ConvertTo-Json -Depth 8),
            (New-Object Text.UTF8Encoding($false)))
        # Rename on the same volume: readers only see a complete JSON document.
        [IO.File]::Move($temporary, $State.ResponsePath)
        $State.Saved = $true
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Set-AgentAskMotion {
    param($Window, [bool]$Enabled)
    $edge = $Window.FindName('EdgeLight')
    $edge.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, $null)
    if ($Enabled) {
        $edge.Visibility = 'Visible'
        $animation = New-Object Windows.Media.Animation.DoubleAnimation
        $animation.From = 0
        $animation.To = -820
        $animation.Duration = [Windows.Duration]::new([TimeSpan]::FromSeconds(14))
        $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animation, 30)
        $edge.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, $animation)
    }
    else { $edge.Visibility = 'Collapsed' }
}

function New-AgentAskWindow {
    param($Request, [string]$ResponsePath)
    $xamlPath = Join-Path $script:AgentAskUiRoot 'window.xaml'
    $context = New-Object Windows.Markup.ParserContext
    $context.BaseUri = [Uri]::new($xamlPath, [UriKind]::Absolute)
    $stream = [IO.File]::OpenRead($xamlPath)
    try { $window = [Windows.Markup.XamlReader]::Load($stream, $context) }
    finally { $stream.Dispose() }
    $window.Title = '{0} | {1} | {2}' -f $Request.title, $Request.agent, $Request.request_id.Substring(0, 8)
    $configPath = Join-Path $script:AgentAskUiRoot '..\config.json'
    if ($null -ne $Request.PSObject.Properties['config_path']) { $configPath = $Request.config_path }
    $config = Read-AgentAskConfig $configPath
    $window.Tag = @{
        Request = $Request; ResponsePath = $ResponsePath; Saved = $false
        ConfigPath = $configPath; Config = $null; EditSnapshot = $null
        ConfigStamp = [IO.File]::GetLastWriteTimeUtc($configPath).Ticks
        Clock = [Diagnostics.Stopwatch]::new(); Timer = $null
    }
    if (-not $config.behavior.enabled) {
        Save-AgentAskResponse $window.Tag 'disabled' $null
        return $window
    }
    $window.FindName('Question').Text = $Request.question
    $window.FindName('AgentName').Text = $Request.agent
    $window.FindName('AgentName').ToolTip = '{0} | {1}' -f $Request.agent, $Request.request_id

    Apply-AgentAskConfig $window $config -Initial

    $window.FindName('DragHandle').Add_MouseLeftButtonDown({
        $owner = [Windows.Window]::GetWindow($this)
        if ($_.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed) { $owner.DragMove() }
    })
    $window.FindName('Answer').Add_TextChanged({
        $owner = [Windows.Window]::GetWindow($this)
        $owner.FindName('Placeholder').Visibility = if ($this.Text.Length) { 'Collapsed' } else { 'Visible' }
    })
    $window.FindName('Submit').Add_Click({
        $owner = [Windows.Window]::GetWindow($this)
        try {
            Save-AgentAskResponse $owner.Tag 'answered' $owner.FindName('Answer').Text
            $owner.Close()
        }
        catch {
            [void][Windows.MessageBox]::Show($owner, $_.Exception.Message,
                'Could not save answer', 'OK', 'Error')
        }
    })
    $window.FindName('Cancel').Add_Click({ [Windows.Window]::GetWindow($this).Close() })
    $window.FindName('Settings').Add_Click({
        $owner = [Windows.Window]::GetWindow($this)
        try {
            if ($owner.FindName('SettingsPopup').IsOpen) { $owner.FindName('SettingsPopup').IsOpen = $false }
            else { Open-AgentAskSettings $owner }
        }
        catch { [void][Windows.MessageBox]::Show($owner, $_.Exception.Message, 'Cannot load settings') }
    })
    # Popup content has its own visual tree. Keep explicit owner references.
    $window.FindName('SettingsPanel').Tag = $window
    $window.FindName('SaveSettings').Tag = $window
    $window.FindName('SaveSettings').Add_Click({
        $owner = $this.Tag
        try {
            $seconds = 0
            if (-not [int]::TryParse($owner.FindName('TimeoutSeconds').Text, [ref]$seconds)) {
                throw 'Wait duration must be a whole number (1-86400 seconds).'
            }
            $edited = [pscustomobject]@{
                appearance = [pscustomobject]@{
                    window_scale = $owner.FindName('WindowScale').Value / 100
                    font_size = [int]$owner.FindName('FontSize').Value
                    edge_animation = [bool]$owner.FindName('MotionToggle').IsChecked
                }
                behavior = [pscustomobject]@{
                    enabled = [bool]$owner.FindName('EnabledToggle').IsChecked
                    topmost = [bool]$owner.FindName('TopmostToggle').IsChecked
                    timeout_enabled = [bool]$owner.FindName('TimeoutToggle').IsChecked
                    timeout_seconds = $seconds
                }
            }
            $saved = Save-AgentAskConfig $owner.Tag.ConfigPath $owner.Tag.EditSnapshot $edited
            $owner.FindName('SettingsPopup').IsOpen = $false
            if (-not $saved.behavior.enabled) {
                Save-AgentAskResponse $owner.Tag 'disabled' $null
                $owner.Close()
            }
            else {
                Apply-AgentAskConfig $owner $saved
                Update-AgentAskLifecycle $owner
                [void]$owner.FindName('Answer').Focus()
            }
        }
        catch { $owner.FindName('SettingsError').Text = $_.Exception.Message }
    })
    $window.FindName('SettingsPanel').Add_PreviewKeyDown({
        if ($_.Key -eq 'Escape') {
            $_.Handled = $true
            $this.Tag.FindName('SettingsPopup').IsOpen = $false
            [void]$this.Tag.FindName('Answer').Focus()
        }
    })
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Tag = $window
    $timer.Add_Tick({ Update-AgentAskLifecycle $this.Tag })
    $window.Tag.Timer = $timer
    $window.Add_ContentRendered({
        $this.Tag.Clock.Restart()
        $this.Tag.Timer.Start()
        Update-AgentAskLifecycle $this
        [void]$this.FindName('Answer').Focus()
    })
    $window.Add_PreviewKeyDown({
        if ($_.Key -eq 'Escape') {
            $_.Handled = $true
            if ($this.FindName('SettingsPopup').IsOpen) {
                $this.FindName('SettingsPopup').IsOpen = $false
                [void]$this.FindName('Answer').Focus()
            }
            else { $this.Close() }
        }
        elseif ($_.Key -eq 'Return' -and
                ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            $_.Handled = $true
            $click = New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)
            $this.FindName('Submit').RaiseEvent($click)
        }
    })
    $window.Add_Closing({
        $closingEvent = $_
        try { Save-AgentAskResponse $this.Tag 'cancelled' $null }
        catch {
            $closingEvent.Cancel = $true
            [void][Windows.MessageBox]::Show($this, $_.Exception.Message,
                'Could not save cancellation', 'OK', 'Error')
        }
    })
    $window.Add_Closed({
        $this.FindName('SettingsPopup').IsOpen = $false
        Set-AgentAskMotion $this $false
        $this.Tag.Timer.Stop()
        $this.Tag.Timer.Tag = $null
        $this.Tag.Clock.Stop()
        $this.FindName('SettingsPanel').Tag = $null
        $this.FindName('SaveSettings').Tag = $null
    })
    return $window
}

# Dot-sourcing exposes the production UI functions to the automated smoke test.
if ($MyInvocation.InvocationName -ne '.') {
    $state = $null
    $window = $null
    try {
        $request = [IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $responsePath = Join-Path ([IO.Path]::GetDirectoryName($RequestPath)) 'response.json'
        $state = @{ Request = $request; ResponsePath = $responsePath; Saved = $false }
        $window = New-AgentAskWindow $request $responsePath
        if (-not $window.Tag.Saved) { [void]$window.ShowDialog() }
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.ToString())
        if ($null -ne $window) { $state = $window.Tag }
        if ($null -ne $state -and -not $state.Saved) {
            Save-AgentAskResponse $state 'error' $null $_.Exception.Message
        }
        exit 1
    }
}
