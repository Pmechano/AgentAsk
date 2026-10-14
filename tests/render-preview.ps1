# Render the production WPF layout to a PNG without desktop capture dependencies.
param([Parameter(Mandatory = $true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ui\ask-window.ps1')
$temporary = Join-Path $env:TEMP ('AgentAsk-preview-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$window = $null
try {
    $request = [pscustomobject]@{
        request_id = [Guid]::NewGuid().ToString('N')
        agent = 'Codex'; title = 'AgentAsk design preview'
        question = ([char]0x4F60).ToString() + ([char]0x597D).ToString() + "!`nA little space for your next idea."
    }
    $window = New-AgentAskWindow $request (Join-Path $temporary 'response.json')
    # Render at the design size, independently of the current monitor's size.
    $window.Width = 936
    $window.Height = 650
    $window.Show()
    $frame = New-Object Windows.Threading.DispatcherFrame
    [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [Windows.Threading.DispatcherPriority]::Background,
        [Action]{ $frame.Continue = $false })
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    $window.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(936, 650, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file = [IO.File]::Create($OutputPath)
    try { $encoder.Save($file) } finally { $file.Dispose() }
    Write-Output 'Preview rendered.'
}
finally {
    if ($null -ne $window -and $window.IsVisible) { $window.Close() }
    if (Test-Path $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
