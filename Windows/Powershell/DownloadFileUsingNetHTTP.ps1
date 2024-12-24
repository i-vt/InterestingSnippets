# Add the necessary .NET DLL (already included in PowerShell)
Add-Type -AssemblyName "System.Net.Http"

# Create an instance of HttpClient
$httpClient = New-Object System.Net.Http.HttpClient

# Specify the URL and file path
$url = "https://example.com/file.zip"
$outputPath = "C:\Path\To\Download\file.zip"

# Download the file asynchronously
$response = $httpClient.GetAsync($url).Result

if ($response.IsSuccessStatusCode) {
    # Save the file
    [System.IO.File]::WriteAllBytes($outputPath, $response.Content.ReadAsByteArrayAsync().Result)
    Write-Output "File downloaded successfully to $outputPath"
} else {
    Write-Error "Failed to download file. HTTP Status: $($response.StatusCode)"
}

# Dispose of the HttpClient
$httpClient.Dispose()

# One liner:
# Add-Type -AssemblyName "System.Net.Http"; $httpClient = New-Object System.Net.Http.HttpClient; $url = "https://example.com/file.zip"; $outputPath = "C:\Path\To\Download\file.zip"; $response = $httpClient.GetAsync($url).Result; if ($response.IsSuccessStatusCode) { [System.IO.File]::WriteAllBytes($outputPath, $response.Content.ReadAsByteArrayAsync().Result); Write-Output "File downloaded successfully to $outputPath"; } else { Write-Error "Failed to download file. HTTP Status: $($response.StatusCode)"; }; $httpClient.Dispose()
