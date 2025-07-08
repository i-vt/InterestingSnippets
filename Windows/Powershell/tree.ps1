# CMD style
tree /F /A


# Powershell 
Get-ChildItem -Recurse | Tree


# Advanced?
function Show-Tree {
    param (
        [string]$Path = ".",
        [int]$Level = 0
    )

    $prefix = " " * ($Level * 4)
    Get-ChildItem -LiteralPath $Path | ForEach-Object {
        Write-Output "$prefix├── $_"
        if ($_.PSIsContainer) {
            Show-Tree -Path $_.FullName -Level ($Level + 1)
        }
    }
}
