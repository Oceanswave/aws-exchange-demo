# Display some AWS set environment variables (there's more, this is just one)
# See https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html#configuration-envvars-runtime
Write-Host AWS_LAMBDA_FUNCTION_NAME=$Env:AWS_LAMBDA_FUNCTION_NAME

$hasInitialized = $false;
## Initialization Phase
if ($hasInitialized -eq $false) {
  try {
    # Import the Exchange Online Management module and connect.
    Import-Module ExchangeOnlineManagement
    Connect-ExchangeOnline -ShowProgress $false -AppId $env:AAD_APPID -CertificateFilePath "$env:CERT_PATH" -CertificatePassword (ConvertTo-SecureString -String $env:CERT_PASSWORD -AsPlainText -Force) -Organization $env:AAD_ORG
    $hasInitialized = $true
  } catch [System.Exception] {
    Write-Error $_.Exception.Message

    # If something went wrong during initialization, call the initialization error API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-initerror
    $errorResponse = @{
      errorMessage = $_.Exception.Message
      errorType = $_.Exception.Type
      stackTrace= @( $_.ScriptStackTrace )
    }
    Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/init/error" -Body (ConvertTo-Json -InputObject $errorResponse -Compress -Depth 3)
    
    # Disconnect from Exchange Online and exit
    Disconnect-ExchangeOnline -Confirm:$false
    exit 1
  }
}

## Invocation Phase
while(1) {
  # Invoke the AWS Lambda runtime API and get information about the current invocation from it
  # See https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html
  $NextInvocationResponse = Invoke-WebRequest "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/next"
  # Some information is contained in the headers...
  $REQUEST_ID = $NextInvocationResponse.Headers['Lambda-Runtime-Aws-Request-Id']
  $DEADLINE_MS = $NextInvocationResponse.Headers['Lambda-Runtime-Deadline-Ms']
  $FUNCTION_ARN = $NextInvocationResponse.Headers['Lambda-Runtime-Invoked-Function-Arn']
  $TRACE_ID = $NextInvocationResponse.Headers['Lambda-Runtime-Trace-Id']
  $CLIENT_CONTEXT = $NextInvocationResponse.Headers['Lambda-Runtime-Client-Context']
  $COGNITO_IDENTITY = $NextInvocationResponse.Headers['Lambda-Runtime-Cognito-Identity']

  # And the response body contains the invocation parameters
  $InvocationParameters = ConvertFrom-Json $NextInvocationResponse.Content -AsHashtable

  # Write this out to the logs so we can see it easily in cloudwatch
  Write-Host "Request Id: $REQUEST_ID"
  Write-Host "Deadline MS: $DEADLINE_MS"
  Write-Host "Function ARN: $FUNCTION_ARN"
  Write-Host "Trace Id: $TRACE_ID"
  Write-Host "Client Context: $CLIENT_CONTEXT"
  Write-Host "Cognito Identity: $COGNITO_IDENTITY"
  Write-Host (ConvertTo-Json -InputObject $InvocationParameters -Compress -Depth 3)

  # Use 'Ryan Howard' or get the value from a route parameter
  $mailContactIdentity = "Ryan Howard"
  if ($InvocationParameters.pathParameters -and ($InvocationParameters.pathParameters.userName -and -not [string]::IsNullOrEmpty($InvocationParameters.pathParameters.userName))) {
    $mailContactIdentity = $InvocationParameters.pathParameters.userName
  }

  try {
    # Call out to exchange to get the information about the user
    Write-Host "Obtaining Mail Contact $mailContactIdentity"
    $mailContact = Get-MailContact -Identity $mailContactIdentity
    $responseBody = (ConvertTo-Json -InputObject $mailContact -Compress -Depth 3)
    
    # Demonstration of executing the .net core 5.0 CLI app that is installed in the image.
    & ./exchange_cli/exchange_cli

    # Create the response. Note that this is the 1.0 format
    # See https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-lambda.html
    $response = @{
      cookies = @()
      isBase64Encoded = $false
      statusCode = 200
      headers = @{
        "content-type" = "application/json"
      }
      body = $responseBody 
    }

    # Now that we're all done, invoke the response API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-response
    Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$REQUEST_ID/response" -Body (ConvertTo-Json -InputObject $response -Compress -Depth 3)
  } catch [System.Exception] {
    Write-Error $_.Exception.Message

    # If something went wrong during invocation, call the invocation error API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-invokeerror
    $errorResponse = @{
      errorMessage = $_.Exception.Message
      errorType = $_.Exception.Type
      stackTrace= @( $_.ScriptStackTrace )
    }
    Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$REQUEST_ID/error" -Body (ConvertTo-Json -InputObject $errorResponse -Compress -Depth 3)
    
    # Disconnect from Exchange Online and exit
    Disconnect-ExchangeOnline -Confirm:$false
    exit 1
  }
}
