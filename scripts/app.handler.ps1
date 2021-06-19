function Initialize-Handler() {
  # Import the Exchange Online Management module and connect.
  Import-Module ExchangeOnlineManagement
  Connect-ExchangeOnline -ShowProgress $false -AppId $Env:AAD_APPID -CertificateFilePath "$Env:CERT_PATH" -CertificatePassword (ConvertTo-SecureString -String $Env:CERT_PASSWORD -AsPlainText -Force) -Organization $Env:AAD_ORG
}

function Close-Handler() {
  # Disconnect from Exchange Online and exit
  Disconnect-ExchangeOnline -Confirm:$false
  Get-PSSession | Remove-PSSession
}

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
      cookies = @()
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