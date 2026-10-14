# Runs actual WinForms event handlers. Windows close automatically; no user answer needed.
param([string]$OutputRoot = $env:TEMP)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ui\ask-window.ps1')
$OutputRoot = Join-Path $OutputRoot ('AgentAsk-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($OutputRoot)
$forms = @()
try {
    foreach ($index in 0..2) {
        $id = [Guid]::NewGuid().ToString('N')
        $request = [pscustomobject]@{
            request_id = $id; agent = "smoke-test-$index"; title = 'AgentAsk automatic test'
            question = "Automatic test $index - closes by itself."
        }
        $form = New-AgentAskWindow $request (Join-Path $OutputRoot "$index.json")
        $forms += $form
        $form.Show()
    }
    [Windows.Forms.Application]::DoEvents()
    if (($forms | Where-Object Visible).Count -ne 3) { throw 'Expected three independent visible windows' }
    $expected = ([string][char]0x4F60) + ([string][char]0x597D) + "`r`nanswer `$()"
    $forms[0].Controls.Find('Answer', $true)[0].Text = $expected
    $forms[0].Controls.Find('Submit', $true)[0].PerformClick()
    $forms[1].Controls.Find('Cancel', $true)[0].PerformClick()
    $forms[2].Close()
    [Windows.Forms.Application]::DoEvents()
    $responses = @(0..2 | ForEach-Object {
        [IO.File]::ReadAllText((Join-Path $OutputRoot "$_.json"), [Text.Encoding]::UTF8) | ConvertFrom-Json
    })
    if ($responses[0].status -ne 'answered' -or $responses[0].answer -cne $expected) { throw 'Answer roundtrip failed' }
    if ($responses[1].status -ne 'cancelled' -or $responses[2].status -ne 'cancelled') { throw 'Cancellation failed' }
    if (@($responses.request_id | Select-Object -Unique).Count -ne 3) { throw 'Request isolation failed' }
    Write-Output 'PASS: three concurrent windows, Unicode answer, submit, cancel, close, JSON isolation.'
}
finally {
    foreach ($form in $forms) { $form.Dispose() }
    if (Test-Path $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
}
