# curl -F "file=@<filename>" http://192.168.56.10:2020/

# Ensure the script is running with administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Please run the PowerShell with administrator privileges."
    break
}

# Set up the listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:2020/")
try {
    $listener.Start()
}
catch {
    Write-Host "Error starting HTTP listener. It might be due to insufficient privileges or the port being in use."
    exit
}

Write-Host "Listening..."

# Handle incoming requests
while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # Check if the request is a POST request
    if ($request.HttpMethod -eq 'POST') {
        Write-Host "Received POST request"

        # Process file upload
        if ($request.ContentType -like 'multipart/form-data*') {
            $boundary = $request.ContentType.Split('=')[1]
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $data = $reader.ReadToEnd()

            # Extract and save the file
            $fileName = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText($fileName, $data.Split("--$boundary")[-3].Split("`r`n")[-3])

            Write-Host "File saved to $fileName"
        }

        # Prepare and send response
        $responseText = 'File received and saved.'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseText)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
    } else {
        # Not a POST request, send a 405 Method Not Allowed response
        $response.StatusCode = 405
        $response.StatusDescription = 'Method Not Allowed'
        $response.Close()
        continue
    }

    $response.Close()
}

# Stop the listener when done
$listener.Stop()
