<#
.SYNOPSIS
    Recursively zips every subfolder under a given path, saving all .zip files into a single output directory, with error handling and logging.

.PARAMETER Path
    The root folder to recurse into. Defaults to the current directory.

.PARAMETER OutputDir
    Where to write the .zip files. Defaults to the current directory.
Zip everything under the current folder, output here

.\RecursiveZip.ps1

Zip all subfolders of D:\Projects, put zips into E:\Archives

.\RecursiveZip.ps1 -Path D:\Projects -OutputDir E:\Archives

From anywhere, reference full script path

C:\Scripts\RecursiveZip.ps1 -Path "C:\My Data" -OutputDir "C:\My Zips
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Path = ".",

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "."
)

# Stop on non-terminating errors inside try blocks
$ErrorActionPreference = 'Stop'

try {
    # Resolve full paths
    $root = Resolve-Path $Path
    $output = Resolve-Path $OutputDir

    # Ensure output directory exists
    if (!(Test-Path $output)) {
        New-Item -Path $output -ItemType Directory | Out-Null
    }
}
catch {
    Write-Error "Failed to initialize paths: $_"
    exit 1
}

# Prepare error log
$logFile = Join-Path $output "zip-errors.log"
if (Test-Path $logFile) { Remove-Item $logFile -Force }
"Log started on $((Get-Date).ToString())" | Out-File -FilePath $logFile

# OPTIONAL TIPS:
# - To skip empty folders, you could wrap the Compress-Archive call in:
#     if (@(Get-ChildItem -Path $dir).Count -gt 0) { ... }
# - To include the root folder itself in the zipping loop, change the directory enumeration to:
#     Get-ChildItem -Path $root -Directory -Recurse , $root

# Process each folder
Get-ChildItem -Path $root -Directory -Recurse | ForEach-Object {
    $dir = $_.FullName

    # Build a safe zip filename
    $relative = $dir.Substring($root.Path.Length).TrimStart('\','/')
    if ([string]::IsNullOrEmpty($relative)) {
        $relative = Split-Path $root -Leaf
    }
    $zipName = $relative -replace '[\\\/]', '_'
    $zipFile = Join-Path $output "$zipName.zip"

    Write-Host "Zipping:`n  Source: $dir`n  Destination: $zipFile" -ForegroundColor Cyan

    try {
        # Ensure we don't fail if the ZIP already exists
        if (Test-Path $zipFile) {
            Remove-Item $zipFile -Force
        }

        # Compress
        Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zipFile -Force

        Write-Host "Successfully created $zipName.zip" -ForegroundColor Green
    }
    catch {
        $msg = "[$((Get-Date).ToString())] ERROR zipping '$dir': $_"
        # Log detailed error
        $msg | Out-File -FilePath $logFile -Append
        # Notify user
        Write-Error "Failed to zip '$dir'. See log: $logFile"
        # Continue with next folder
    }
}

Write-Host "`nAll done! ZIP files are in $($output.Path)" -ForegroundColor Green
Write-Host "Any errors were logged to $logFile" -ForegroundColor Yellow
