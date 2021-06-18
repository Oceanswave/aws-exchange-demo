Write-Host AWS_LAMBDA_FUNCTION_NAME=$Env:AWS_LAMBDA_FUNCTION_NAME
$NextInvocationResponse = Invoke-WebRequest "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/next"
$REQUEST_ID = $NextInvocationResponse.Headers['Lambda-Runtime-Aws-Request-Id']
$DEADLINE_MS = $NextInvocationResponse.Headers['Lambda-Runtime-Deadline-Ms']
$FUNCTION_ARN = $NextInvocationResponse.Headers['Lambda-Runtime-Invoked-Function-Arn']
$TRACE_ID = $NextInvocationResponse.Headers['Lambda-Runtime-Trace-Id']
$CLIENT_CONTEXT = $NextInvocationResponse.Headers['Lambda-Runtime-Client-Context']
$COGNITO_IDENTITY = $NextInvocationResponse.Headers['Lambda-Runtime-Cognito-Identity']

$InvocationParameters = ConvertFrom-Json $NextInvocationResponse.Content -AsHashtable
Write-Host "Request Id: $REQUEST_ID"
Write-Host "Deadline MS: $DEADLINE_MS"
Write-Host "Function ARN: $FUNCTION_ARN"
Write-Host "Trace Id: $TRACE_ID"
Write-Host "Client Context: $CLIENT_CONTEXT"
Write-Host "Cognito Identity: $COGNITO_IDENTITY"
Write-Host (ConvertTo-Json -InputObject $InvocationParameters -Compress -Depth 3)

Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowProgress $false -AppId $env:AAD_APPID -CertificateFilePath "$env:CERT_PATH" -CertificatePassword (ConvertTo-SecureString -String $env:CERT_PASSWORD -AsPlainText -Force) -Organization $env:AAD_ORG

try {  
  Get-MailContact -Identity "Ryan Howard" | Format-List
  
  & ./exchange_cli/exchange_cli

  $response = @{
    statusCode = 200
    body = "Success"
  }

  Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$REQUEST_ID/response" -Body (ConvertTo-Json -InputObject $response -Compress -Depth 3)
} catch [System.Exception] {
  $errorResponse = @{
    errorMessage = $_.Exception.Message
    errorType = $_.Exception.Type
    stackTrace= @( $_.ScriptStackTrace )
  }
  Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$REQUEST_ID/error" -Body (ConvertTo-Json -InputObject $errorResponse -Compress -Depth 3)
} finally {
  Disconnect-ExchangeOnline -Confirm:$false
}
