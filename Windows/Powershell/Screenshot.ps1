Add-Type -Namespace Win32 -Name DpiHelper -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("shcore.dll")]
public static extern int SetProcessDpiAwareness(int value);
"@

try {
    [Win32.DpiHelper]::SetProcessDpiAwareness(2) | Out-Null
} catch {
    [Win32.DpiHelper]::SetProcessDPIAware() | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screens = [System.Windows.Forms.Screen]::AllScreens
$totalWidth = 0
$maxHeight = 0

foreach ($screen in $screens) {
    $totalWidth += $screen.Bounds.Width
    if ($screen.Bounds.Height -gt $maxHeight) {
        $maxHeight = $screen.Bounds.Height
    }
}

$bitmap = New-Object System.Drawing.Bitmap $totalWidth, $maxHeight
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

$xOffset = 0

foreach ($screen in $screens) {
    $graphics.CopyFromScreen(
        $screen.Bounds.Location.X,
        $screen.Bounds.Location.Y,
        $xOffset,
        0,
        $screen.Bounds.Size
    )
    $xOffset += $screen.Bounds.Width
}

$outputDir = "$env:TEMP\Screenshots"
$outputPath = "$outputDir\Screenshot.png"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

try {
    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "Screenshot saved to $outputPath"
} catch {
    Write-Error "Failed to save screenshot: $_"
}

$graphics.Dispose()
$bitmap.Dispose()
