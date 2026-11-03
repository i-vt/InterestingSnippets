# UploadMultipleFilesChunkedViaPOST.ps1
# Uploads the .dat files to the server via HTTP POST (multipart/form-data).
# Files larger than $ChunkThreshold are split into chunks; chunks are uploaded
# MULTI-THREADED via a pool of concurrent curl.exe processes ($MaxConcurrent).
# Each chunk POST carries: chunk data + filename, index, total chunks.
# Works on Windows PowerShell 5.1 and PowerShell 7+.

# --- Adjust these if needed ---
$ServerUrl      = "http://192.168.56.1:2020/upload"  # change the path if your endpoint differs
$SourceDir      = "C:\Users\user1\Documents"
$ChunkThreshold = 100MB      # files bigger than this are uploaded in chunks
$ChunkSize      = 25MB       # size of each chunk
$MaxRetries     = 3          # attempts per chunk before giving up
$MaxConcurrent  = 4          # number of chunks uploaded in parallel

$Files = @(
    "2b152adf_1KB.dat",
    "50988aa7_5GB.dat",
    "f8bf749a_500MB.dat"
)

function Invoke-SingleUpload {
    param([string]$Path)

    curl.exe -sS -X POST $ServerUrl -F "file=@$Path" `
        -w "`n-> HTTP %{http_code} | %{size_upload} bytes sent | %{time_total}s`n"

    return ($LASTEXITCODE -eq 0)
}

function Split-FileIntoChunks {
    param([string]$Path, [string]$TmpDir, [string]$Prefix)

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] $ChunkSize
        $index  = 0
        while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $out = Join-Path $TmpDir ("{0}_chunk_{1:D8}" -f $Prefix, $index)
            [System.IO.File]::WriteAllBytes($out, $buffer[0..($read - 1)])
            $index++
        }
        return $index
    }
    finally {
        $fs.Dispose()
    }
}

function Invoke-ChunkedUpload {
    param([string]$Path)

    $fileName    = [IO.Path]::GetFileName($Path)
    $fileSize    = (Get-Item $Path).Length
    $totalChunks = [math]::Ceiling($fileSize / $ChunkSize)
    $tmpDir      = Join-Path $env:TEMP ("upload_" + [guid]::NewGuid().ToString('N').Substring(0, 8))

    # chunk naming: <basename[:20]><ext>_<session-guid>_chunk_NNNNNNNN
    # e.g. 23faklfj234232134123.dat_39e77ce1-cd5f-49ce-8709-07e2fa783452_chunk_00000000
    $sessionGuid = [guid]::NewGuid().ToString()
    $base        = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $ext         = [IO.Path]::GetExtension($fileName)
    $shortBase   = if ($base.Length -gt 20) { $base.Substring(0, 20) } else { $base }
    $chunkPrefix = "$shortBase$ext" + "_" + $sessionGuid

    Write-Host "  Chunking into $totalChunks chunks of $([math]::Round($ChunkSize/1MB)) MB each..."
    Write-Host "  Chunk prefix: $chunkPrefix"
    New-Item -ItemType Directory -Path $tmpDir | Out-Null

    try {
        $totalChunks = Split-FileIntoChunks -Path $Path -TmpDir $tmpDir -Prefix $chunkPrefix

        # --- phase 1: enqueue all chunk indexes ---
        $queue = New-Object 'System.Collections.Generic.Queue[int]'
        for ($i = 0; $i -lt $totalChunks; $i++) { $queue.Enqueue($i) }

        # --- phase 2: upload with a fixed-size process pool ---
        $running      = New-Object 'System.Collections.Generic.List[object]'
        $attempts     = @{}
        $done         = 0
        $failedChunks = @()

        while ($queue.Count -gt 0 -or $running.Count -gt 0) {

            # fill free slots with new chunk uploads
            while ($queue.Count -gt 0 -and $running.Count -lt $MaxConcurrent) {
                $index     = $queue.Dequeue()
                $chunkPath = Join-Path $tmpDir ("{0}_chunk_{1:D8}" -f $chunkPrefix, $index)
                if (-not $attempts.ContainsKey($index)) { $attempts[$index] = 0 }
                $attempts[$index]++

                Write-Host ("  [{0}/{1}] START chunk {2} (attempt {3})" -f ($done + 1), $totalChunks, $index, $attempts[$index])

                # each process gets its own log files to avoid garbled console output
                $outLog = "$chunkPath.stdout.log"
                $errLog = "$chunkPath.stderr.log"
                $arguments = '-sS -X POST "{0}" -F "chunk=@{1}" -F "filename={2}" -F "index={3}" -F "total={4}" -o "{5}"' -f `
                    $ServerUrl, $chunkPath, $fileName, $index, $totalChunks, $outLog

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName               = "curl.exe"
                $psi.Arguments              = $arguments
                $psi.UseShellExecute        = $false
                $psi.RedirectStandardError  = $true
                $psi.CreateNoWindow         = $true
                $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

                $proc = [System.Diagnostics.Process]::Start($psi)
                # do NOT wait here - the poll loop below collects finished processes
                $running.Add(@{ Proc = $proc; Index = $index; ChunkPath = $chunkPath; OutLog = $outLog; ErrLog = $errLog })
            }

            # wait until at least one process exits
            while ($running.Count -gt 0 -and -not ($running | Where-Object { $_.Proc.HasExited })) {
                Start-Sleep -Milliseconds 200
            }

            # collect finished processes
            $finished = @($running | Where-Object { $_.Proc.HasExited })
            foreach ($entry in $finished) {
                $running.Remove($entry)
                $exitCode = $entry.Proc.ExitCode
                Remove-Item $entry.ChunkPath -Force -ErrorAction SilentlyContinue

                if ($exitCode -eq 0) {
                    $done++
                    $summary = ''
                    if (Test-Path $entry.OutLog) {
                        # last line of the response body / write-out output, if any
                        $summary = (Get-Content $entry.OutLog -Tail 1 -ErrorAction SilentlyContinue)
                        Remove-Item $entry.OutLog -Force -ErrorAction SilentlyContinue
                    }
                    Write-Host ("  [{0}/{1}] DONE  chunk {2} (exit 0) {3}" -f $done, $totalChunks, $entry.Index, $summary) -ForegroundColor Green
                }
                else {
                    $err = ''
                    if (Test-Path $entry.ErrLog) {
                        $err = (Get-Content $entry.ErrLog -Raw -ErrorAction SilentlyContinue).Trim()
                        Remove-Item $entry.ErrLog -Force -ErrorAction SilentlyContinue
                    }
                    if ($attempts[$entry.Index] -lt $MaxRetries) {
                        Write-Warning ("  chunk {0} failed (exit {1}): {2} -- requeuing" -f $entry.Index, $exitCode, $err)
                        $queue.Enqueue($entry.Index)
                    }
                    else {
                        Write-Error ("  chunk {0} failed after {1} attempts (exit {2}): {3}" -f $entry.Index, $MaxRetries, $exitCode, $err)
                        $failedChunks += $entry.Index
                    }
                }
            }
        }

        if ($failedChunks.Count -eq 0) {
            Write-Host "  All $totalChunks chunks of $fileName uploaded. Server should now reassemble." -ForegroundColor Green
            return $true
        }
        else {
            Write-Error ("  {0} chunk(s) of {1} failed: {2}" -f $failedChunks.Count, $fileName, ($failedChunks -join ', '))
            return $false
        }
    }
    finally {
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
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
    }
    else {
        if (-not (Invoke-SingleUpload -Path $path)) {
            Write-Error "curl failed for $file (exit code $LASTEXITCODE)"
        }
    }
}

Write-Host "`nDone."
