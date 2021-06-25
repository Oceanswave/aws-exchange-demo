# Cmdlet that is called when the Lambda handler is initialized
function Initialize-Handler() {
  # Import AWS Cmdlets
  Import-Module AWS.Tools.Installer
  Install-AWSToolsModule AWS.Tools.SQS -CleanUp -Force
  # Import the Exchange Online Management module and connect.
  Import-Module ExchangeOnlineManagement
  Connect-ExchangeOnline -ShowProgress $false -AppId $Env:AAD_APPID -CertificateFilePath "$Env:CERT_PATH" -CertificatePassword (ConvertTo-SecureString -String $Env:CERT_PASSWORD -AsPlainText -Force) -Organization $Env:AAD_ORG
}

# Cmdlet that is called when the Lambda handler is closing because of an error
function Close-Handler() {
  # Disconnect from Exchange Online and exit
  Disconnect-ExchangeOnline -Confirm:$false
  Get-PSSession | Remove-PSSession
}

function Invoke-ExchangeProcessor() {
  param ([HashTable]$InvocationParameters, [HashTable]$InvocationInfo)

  # This example is a bit contrived, however, if the $InvocationParameters contains 
  # a top-level 'Records' object then we know (in this contrived situation) that
  # we're intending to perform an update using queued information from SQS rather 
  #than a HTTP-based request.

  if ($InvocationParameters.Records -and $InvocationParameters.Records -is [array]) {
    $Processed = 0
    $Result = [System.Collections.ArrayList]@()
    Write-Information "Processing..."
    foreach ($Record in $InvocationParameters.Records) {
      $Data = ConvertFrom-Json $Record.body -AsHashtable
      $Result.Add((Import-Contact -Data $Data))
      $Processed++
    }

    $ResponseObject = @{
      Processed = $Processed
      Result = $Result
    }

    Write-Information "Processed $Processed records."

    # Add a message to the out queue
    if ($Env:DESTINATION_SQS_URL) {
      Write-Information "Adding response to $Env:DESTINATION_SQS_URL"
      $SQSResult = (Send-SQSMessage -MessageBody (ConvertTo-Json -InputObject $ResponseObject -Compress -Depth 3) -QueueUrl "$Env:DESTINATION_SQS_URL")
      Write-Information $SQSResult
    }

    # Since the SQS Invocation was not HTTP related, just return our json-encoded response object
    # In a better example, we might save this to a S3 bucket - One that triggers an SES email to be sent
    return (ConvertTo-Json -InputObject $ResponseObject -Compress -Depth 3)
  }

  # Otherwise we're coming from API Gateway as a direct HTTP API request/response, Get a contact
  return Get-Contact -InvocationParameters $InvocationParameters -InvocationInfo $InvocationInfo
}

# Example function to demonstrate updating a Mailbox
function Import-Contact {
  param ([HashTable]$Data)

  # TODO: Do something with the data.
  Write-Information (ConvertTo-Json -InputObject $Data -Compress -Depth 3)
  return @{
    Status = "OK"
  }
}

# Example function to demonstrate retrieving a Mail Contact from Exchange Online
function Get-Contact {
  param ([HashTable]$InvocationParameters, [HashTable]$InvocationInfo)
  # Use 'Ryan Howard' or get the value from a route parameter
  $MailContactIdentity = "Ryan Howard"
  if ($InvocationParameters.pathParameters -and ($InvocationParameters.pathParameters.userName -and -not [string]::IsNullOrEmpty($InvocationParameters.pathParameters.userName))) {
    $MailContactIdentity = [System.Web.HttpUtility]::UrlDecode($InvocationParameters.pathParameters.userName)
  }

  # Call out to exchange to get the information about the user
  Write-Information "Obtaining Mail Contact $MailContactIdentity"
  try {
    $MailContact = Get-MailContact -Identity $MailContactIdentity
  } catch {
    return @{
      isBase64Encoded = $false
      statusCode = 404
      headers = @{
        "content-type" = "application/json"
      }
      body = $_.Exception.Message
    }
  }

  # Demonstration of executing the .net core 5.0 CLI app that is installed in the image.
  # Interestingly enough, it appears as though anything written to std out is also picked up and used as the response, such as when invoking via & "$PWD/exchange_cli/exchange_cli"
  $CliOutput = Invoke-Process -FilePath "$PWD/exchange_cli/exchange_cli"

  $ResponseObject = @{
    Contact = $MailContact
    Output = $CliOutput
  }

  # Create the response. Note that this is the 2.0 format
  # See https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-output-format
  return  @{
    isBase64Encoded = $false
    statusCode = 200
    headers = @{
      "content-type" = "application/json"
    }
    body = (ConvertTo-Json -InputObject $ResponseObject -Compress -Depth 3)
  }
}

Function Invoke-Process ($FilePath, $ArgumentList)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $FilePath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $ArgumentList
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    [PSCustomObject]@{
        stdout = $p.StandardOutput.ReadToEnd()
        stderr = $p.StandardError.ReadToEnd()
        ExitCode = $p.ExitCode
    }
}