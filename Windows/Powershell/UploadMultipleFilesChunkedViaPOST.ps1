# Upload-Files.ps1
# Uploads the three .dat files to the server via HTTP POST (multipart/form-data).
# Files larger than $ChunkThreshold are split into chunks and uploaded one by one,
# each POST carrying the chunk data plus metadata (filename, index, total chunks)
# so the server can reassemble the original file.
# Uploads use curl.exe (ships with Windows 10/11), which streams efficiently.

# --- Adjust these if needed ---
$ServerUrl      = "http://192.168.56.1:2020/upload"  # change the path if your endpoint differs
$SourceDir      = "C:\Users\user1\Documents"
$ChunkThreshold = 100MB      # files bigger than this are uploaded in chunks
$ChunkSize      = 25MB      # size of each chunk
$MaxRetries     = 3          # retry attempts per chunk

$Files = @(
    "2b152adf_1KB.dat",
    "50988aa7_5GB.dat",
    "f8bf749a_500MB.dat"
)

function Invoke-SingleUpload {
    param([string]$Path)

    # -F sends the file as multipart/form-data (field name: "file")
    # -sS: quiet but report errors; -w: summary line after the transfer
    curl.exe -sS -X POST $ServerUrl -F "file=@$Path" `
        -w "`n-> HTTP %{http_code} | %{size_upload} bytes sent | %{time_total}s`n"

    return ($LASTEXITCODE -eq 0)
}

function Invoke-ChunkedUpload {
    param([string]$Path)

    $fileName  = [IO.Path]::GetFileName($Path)
    $fileSize  = (Get-Item $Path).Length
    $totalChunks = [math]::Ceiling($fileSize / $ChunkSize)
    $tmpDir    = Join-Path $env:TEMP ("upload_" + [guid]::NewGuid().ToString('N').Substring(0, 8))

    Write-Host "  Chunking into $totalChunks chunks of $([math]::Round($ChunkSize/1MB)) MB each..."

    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    $fs = [System.IO.File]::OpenRead($Path)

    try {
        $buffer = New-Object byte[] $ChunkSize

        for ($i = 0; $i -lt $totalChunks; $i++) {
            $read = $fs.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }

            $chunkPath = Join-Path $tmpDir ("chunk_{0:D5}" -f $i)
            [System.IO.File]::WriteAllBytes($chunkPath, $buffer[0..($read - 1)])

            $attempt = 0
            $ok = $false
            while (-not $ok -and $attempt -lt $MaxRetries) {
                $attempt++
                Write-Host ("  Uploading chunk {0}/{1} ({2:N1} MB), attempt {3}..." -f `
                    ($i + 1), $totalChunks, ($read / 1MB), $attempt)

                curl.exe -sS -X POST $ServerUrl `
                    -F "chunk=@$chunkPath" `
                    -F "filename=$fileName" `
                    -F "index=$i" `
                    -F "total=$totalChunks" `
                    -w "`n  -> HTTP %{http_code} | %{size_upload} bytes | %{time_total}s`n"

                $ok = ($LASTEXITCODE -eq 0)
                if (-not $ok) { Start-Sleep -Seconds 2 }
            }

            Remove-Item $chunkPath -Force

            if (-not $ok) {
                Write-Error "Chunk $i of $fileName failed after $MaxRetries attempts - aborting this file."
                return $false
            }
        }

        Write-Host "  All chunks of $fileName uploaded. Server should now reassemble."
        return $true
    }
    finally {
        $fs.Dispose()
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    }
}

foreach ($file in $Files) {
    $path = Join-Path $SourceDir $file

    if (-not (Test-Path $path)) {
        Write-Warning "File not found, skipping: $path"
        continue
    }

    $sizeMB = [math]::Round((Get-Item $path).Length / 1MB, 2)
    Write-Host "`n=== Uploading $file ($sizeMB MB) ===" -ForegroundColor Cyan

    if ((Get-Item $path).Length -gt $ChunkThreshold) {
        Invoke-ChunkedUpload -Path $path | Out-Null
    } else {
        if (-not (Invoke-SingleUpload -Path $path)) {
            Write-Error "curl failed for $file (exit code $LASTEXITCODE)"
        }
    }
}

Write-Host "`nDone."
