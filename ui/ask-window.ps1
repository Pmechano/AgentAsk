param([string]$RequestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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

function New-AgentAskWindow {
    param($Request, [string]$ResponsePath)
    $form = New-Object Windows.Forms.Form
    $form.Text = '{0} | {1} | {2}' -f $Request.title, $Request.agent, $Request.request_id.Substring(0, 8)
    $form.Size = New-Object Drawing.Size(760, 660)
    $form.MinimumSize = New-Object Drawing.Size(620, 520)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Segoe UI', 10)
    $form.KeyPreview = $true
    $form.ShowInTaskbar = $true
    $form.Tag = @{
        Request = $Request; ResponsePath = $ResponsePath; Saved = $false
    }

    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object Windows.Forms.Padding(16)
    $layout.ColumnCount = 1
    $layout.RowCount = 6
    foreach ($style in @(
        (New-Object Windows.Forms.RowStyle('Absolute', 36)),
        (New-Object Windows.Forms.RowStyle('Percent', 50)),
        (New-Object Windows.Forms.RowStyle('Absolute', 32)),
        (New-Object Windows.Forms.RowStyle('Percent', 50)),
        (New-Object Windows.Forms.RowStyle('Absolute', 28)),
        (New-Object Windows.Forms.RowStyle('Absolute', 44))
    )) { [void]$layout.RowStyles.Add($style) }

    $context = New-Object Windows.Forms.Label
    $context.Text = 'Agent: {0}    Request: {1}' -f $Request.agent, $Request.request_id
    $context.Dock = 'Fill'
    $context.AutoEllipsis = $true
    $layout.Controls.Add($context, 0, 0)

    $question = New-Object Windows.Forms.TextBox
    $question.Name = 'Question'
    $question.Multiline = $true
    $question.ReadOnly = $true
    $question.ScrollBars = 'Vertical'
    $question.Dock = 'Fill'
    $question.TabStop = $false
    $question.Text = $Request.question -replace "`r?`n", "`r`n"
    $layout.Controls.Add($question, 0, 1)

    $label = New-Object Windows.Forms.Label
    $label.Text = 'Your answer:'
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleLeft'
    $layout.Controls.Add($label, 0, 2)

    $answer = New-Object Windows.Forms.TextBox
    $answer.Name = 'Answer'
    $answer.Multiline = $true
    $answer.AcceptsReturn = $true
    $answer.ScrollBars = 'Vertical'
    $answer.Dock = 'Fill'
    $answer.MaxLength = 0
    $layout.Controls.Add($answer, 0, 3)

    $hint = New-Object Windows.Forms.Label
    $hint.Text = 'Ctrl+Enter: submit    Esc / close: cancel'
    $hint.Dock = 'Fill'
    $layout.Controls.Add($hint, 0, 4)

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Fill'
    $buttons.FlowDirection = 'RightToLeft'
    $submit = New-Object Windows.Forms.Button
    $submit.Name = 'Submit'
    $submit.Text = 'Submit'
    $submit.Size = New-Object Drawing.Size(108, 32)
    $submit.Add_Click({
        $window = $this.FindForm()
        try {
            $inputBox = $window.Controls.Find('Answer', $true)[0]
            Save-AgentAskResponse $window.Tag 'answered' $inputBox.Text
            $window.Close()
        }
        catch {
            [void][Windows.Forms.MessageBox]::Show($window, $_.Exception.Message,
                'Could not save answer', 'OK', 'Error')
        }
    })
    $cancel = New-Object Windows.Forms.Button
    $cancel.Name = 'Cancel'
    $cancel.Text = 'Cancel'
    $cancel.Size = New-Object Drawing.Size(108, 32)
    $cancel.Add_Click({ $this.FindForm().Close() })
    $buttons.Controls.Add($submit)
    $buttons.Controls.Add($cancel)
    $form.CancelButton = $cancel
    $layout.Controls.Add($buttons, 0, 5)
    $form.Controls.Add($layout)

    $form.Add_Shown({ [void]$this.Controls.Find('Answer', $true)[0].Focus() })
    $form.Add_KeyDown({
        if ($_.Control -and $_.KeyCode -eq 'Enter') {
            $_.SuppressKeyPress = $true
            $this.Controls.Find('Submit', $true)[0].PerformClick()
        }
    })
    $form.Add_FormClosing({
        $closingEvent = $_
        try { Save-AgentAskResponse $this.Tag 'cancelled' $null }
        catch {
            $closingEvent.Cancel = $true
            [void][Windows.Forms.MessageBox]::Show($this, $_.Exception.Message,
                'Could not save cancellation', 'OK', 'Error')
        }
    })
    return $form
}

# Dot-sourcing exposes the same UI functions to the smoke test without opening a window.
if ($MyInvocation.InvocationName -ne '.') {
    $state = $null
    $form = $null
    try {
        $request = [IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $responsePath = Join-Path ([IO.Path]::GetDirectoryName($RequestPath)) 'response.json'
        $state = @{ Request = $request; ResponsePath = $responsePath; Saved = $false }
        $form = New-AgentAskWindow $request $responsePath
        [void]$form.ShowDialog()
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.ToString())
        if ($null -ne $form) { $state = $form.Tag }
        if ($null -ne $state -and -not $state.Saved) {
            Save-AgentAskResponse $state 'error' $null $_.Exception.Message
        }
        exit 1
    }
    finally { if ($null -ne $form) { $form.Dispose() } }
}
