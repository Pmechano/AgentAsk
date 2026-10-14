# Render the production WPF layout to a PNG without desktop capture dependencies.
param([Parameter(Mandatory = $true)][string]$OutputPath, [switch]$Settings)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ui\ask-window.ps1')
$temporary = Join-Path $env:TEMP ('AgentAsk-preview-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$window = $null
try {
    $request = [pscustomobject]@{
        config_path = (Join-Path $temporary 'config.json')
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
    if ($Settings) {
        Open-AgentAskSettings $window
        $window.UpdateLayout()
    }
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(936, 650, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    if ($Settings) {
        $panel = $window.FindName('SettingsPanel')
        $panel.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $panel.Arrange([Windows.Rect]::new(0, 0, $panel.DesiredSize.Width, $panel.DesiredSize.Height))
        $panel.UpdateLayout()
        $bounds = $panel.LayoutTransform.TransformBounds([Windows.Rect]::new(0, 0, $panel.ActualWidth, $panel.ActualHeight))
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(
            [int][Math]::Ceiling($bounds.Width + 24), [int][Math]::Ceiling($bounds.Height + 24),
            96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $drawing = New-Object Windows.Media.DrawingVisual
        $canvas = $drawing.RenderOpen()
        try {
            $canvas.DrawRectangle([Windows.Media.VisualBrush]::new($panel), $null,
                [Windows.Rect]::new(12, 12, $bounds.Width, $bounds.Height))
        }
        finally { $canvas.Close() }
        $bitmap.Render($drawing)
    }
    else { $bitmap.Render($window) }
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
