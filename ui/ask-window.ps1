param([string]$RequestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
$script:AgentAskUiRoot = $PSScriptRoot

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
    $window.Tag = @{
        Request = $Request; ResponsePath = $ResponsePath; Saved = $false
    }
    $window.FindName('Question').Text = $Request.question
    $window.FindName('AgentName').Text = $Request.agent
    $window.FindName('AgentName').ToolTip = '{0} | {1}' -f $Request.agent, $Request.request_id

    # Fit a small display without changing the hexagon or clipping its controls.
    $work = [Windows.SystemParameters]::WorkArea
    $scale = [Math]::Min(1, [Math]::Min(($work.Width - 24) / 936, ($work.Height - 24) / 650))
    $window.Width = 936 * $scale
    $window.Height = 650 * $scale
    $offset = ([Convert]::ToInt32($Request.request_id.Substring(0, 2), 16) % 5 - 2) * 16
    $window.Left = [Math]::Max($work.Left, [Math]::Min($work.Right - $window.Width,
        $work.Left + ($work.Width - $window.Width) / 2 + $offset))
    $window.Top = [Math]::Max($work.Top, [Math]::Min($work.Bottom - $window.Height,
        $work.Top + ($work.Height - $window.Height) / 2 + $offset))

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
        $owner.FindName('SettingsPopup').IsOpen = -not $owner.FindName('SettingsPopup').IsOpen
    })
    # Popup content has a separate visual tree; Tag identifies its owning window.
    $motion = $window.FindName('MotionToggle')
    $motion.Tag = $window
    $motion.IsChecked = [Windows.SystemParameters]::ClientAreaAnimation
    $motion.Add_Checked({ Set-AgentAskMotion $this.Tag $true })
    $motion.Add_Unchecked({ Set-AgentAskMotion $this.Tag $false })
    $motion.Add_PreviewKeyDown({
        if ($_.Key -eq 'Escape') {
            $_.Handled = $true
            $this.Tag.FindName('SettingsPopup').IsOpen = $false
            [void]$this.Tag.FindName('Answer').Focus()
        }
    })
    $window.Add_ContentRendered({
        Set-AgentAskMotion $this ([bool]$this.FindName('MotionToggle').IsChecked)
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
        $this.FindName('MotionToggle').Tag = $null
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
        [void]$window.ShowDialog()
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
