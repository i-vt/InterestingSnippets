$FilePath = "C:\Temp\test.txt"
$FileName = [System.IO.Path]::GetFileName($FilePath)
$Boundary = [System.Guid]::NewGuid().ToString("N")
$LF = "`r`n"

# Build the multipart content parts
$Part1 = "--$Boundary$LF"
$Part1 += "Content-Disposition: form-data; name=`"file`"; filename=`"$FileName`"$LF"
$Part1 += "Content-Type: application/octet-stream$LF$LF"

$Part3 = "$LF--$Boundary--$LF"

# Convert to byte arrays
$Part1Bytes = [System.Text.Encoding]::UTF8.GetBytes($Part1)
$FileBytes = [System.IO.File]::ReadAllBytes($FilePath)
$Part3Bytes = [System.Text.Encoding]::UTF8.GetBytes($Part3)

# Use MemoryStream to combine everything
$Stream = New-Object System.IO.MemoryStream
$Stream.Write($Part1Bytes, 0, $Part1Bytes.Length)
$Stream.Write($FileBytes, 0, $FileBytes.Length)
$Stream.Write($Part3Bytes, 0, $Part3Bytes.Length)
$Stream.Seek(0, 'Begin') | Out-Null

# Prepare headers
$Headers = @{
    "Content-Type" = "multipart/form-data; boundary=$Boundary"
    "Content-Length" = $Stream.Length
}

# Send POST request
$response = Invoke-RestMethod -Uri "http://192.168.56.1:2020/" -Method Post -Headers $Headers -Body $Stream

# Output response
Write-Output $response
