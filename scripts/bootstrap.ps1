$ErrorActionPreference='Stop';
$ProgressPreference='SilentlyContinue';
$InformationPreference=($Env:PS_ENV -eq "production" ? 'SilentlyContinue' : 'Continue')
$VerbosePreference=($Env:PS_VERBOSE -eq "true" ? 'Continue' : 'SilentlyContinue')

# Display some AWS set environment variables (there's more, this is just the ones aiding in debugging)
# See https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html#configuration-envvars-runtime
Write-Information AWS_LAMBDA_FUNCTION_NAME=$Env:AWS_LAMBDA_FUNCTION_NAME
Write-Information AWS_LAMBDA_FUNCTION_MEMORY_SIZE=$Env:AWS_LAMBDA_FUNCTION_MEMORY_SIZE
Write-Information AWS_LAMBDA_FUNCTION_VERSION=$Env:AWS_LAMBDA_FUNCTION_VERSION
Write-Information TZ=$Env:TZ
Write-Information LAMBDA_TASK_ROOT=$Env:LAMBDA_TASK_ROOT
Write-Information _HANDLER=$Env:_HANDLER

function Invoke-PreInitialization {
  try {
    if ([string]::IsNullOrEmpty($Env:PS_HandlerFunction)) {
      $PS_HandlerFunction = ($Env:_HANDLER | cut -d. -f1)
    } else {
      $PS_HandlerFunction = $Env:PS_HandlerFunction
    }

    if ([string]::IsNullOrEmpty($PS_HandlerFunction)) {
      throw "A handler function must be defined either as the lambda handler or as a PS_HandlerFunction environment variable."
    }

    if ([string]::IsNullOrEmpty($Env:PS_HandlerScript)) {
      if ([string]::IsNullOrEmpty($Env:LAMBDA_TASK_ROOT)) {
        $PS_HandlerScriptPath = "$PWD/$PS_HandlerFunction.ps1"
      } else {
        $PS_HandlerScriptPath = "$Env:LAMBDA_TASK_ROOT/$PS_HandlerFunction.ps1"
      }
    } else {
      $PS_HandlerScriptPath = "$PWD/$Env:PS_HandlerScript"
    }
    
    if (!(Test-Path -Path $PS_HandlerScriptPath -PathType Leaf)) {
      throw "A handler file could not be located at $PS_HandlerScriptPath"
    }

    Write-Information "Using handler function named '$PS_HandlerFunction' located in '$PS_HandlerScriptPath'"
    return @($PS_HandlerFunction, $PS_HandlerScriptPath)
  } catch {
    # If something went wrong during pre-initialization, call the initialization error API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-initerror
    $PreInitializationError = @{
      errorMessage = $_.Exception.Message
      errorType = $_.Exception.Type
      stackTrace= @( $_.ScriptStackTrace )
    }

    $PreInitializationErrorJson = (ConvertTo-Json -InputObject $PreInitializationError -Compress -Depth 3)
    Write-Error $PreInitializationErrorJson
    Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/init/error" -Body $PreInitializationErrorJson
    exit 1
  }
}

function Invoke-Initialization {
  try {
    # If a Initialize-Handler function exists, call it
    if (Get-Command Initialize-Handler -ErrorAction SilentlyContinue) {
      Write-Information "Invoking Initialize-Handler"
      Initialize-Handler
      Write-Information "Completed Initialize-Handler"
    }

    return $true
  } catch {

    # If something went wrong during initialization, call the initialization error API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-initerror
    $InitializationError = @{
      errorMessage = $_.Exception.Message
      errorType = $_.Exception.Type
      stackTrace= @( $_.ScriptStackTrace )
    }

    $InitializationErrorJson = (ConvertTo-Json -InputObject $InitializationError -Compress -Depth 3)
    Write-Error $InitializationErrorJson
    Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/init/error" -Body $InitializationErrorJson
    
    # Invoke the Close-Handler command if it was defined
    if (Get-Command Close-Handler -ErrorAction SilentlyContinue) {
      Write-Information "Invoking Close-Handler"
      Close-Handler
      Write-Information "Completed Close-Handler"
    }
    exit 1
  }
}

function Invoke-HandlerFunction {
  param (
    [String]$PS_HandlerFunction,
    [HashTable]$InvocationParameters,
    [HashTable]$InvocationInfo
  )
  $REQUEST_ID = $InvocationInfo.RequestId

  try {
    $InvocationResponse = $null;

    # Call the invocation handler
    if (Get-Command $PS_HandlerFunction) {
      Write-Information "Invoking $PS_HandlerFunction"
      $InvocationResponse = (&$PS_HandlerFunction -InvocationParameters $InvocationParameters -InvocationInfo $InvocationInfo )
      Write-Information "Completed $PS_HandlerFunction"
    }

    if ($null -eq $InvocationResponse) {
      # See https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-output-format
      $InvocationResponse = @{
        isBase64Encoded = $false
        statusCode = 200
        body = ""
      }
    }

    # Now that we're all done, invoke the response API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-response
    $InvocationResponseResponse = Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$REQUEST_ID/response" -Body (ConvertTo-Json -InputObject $InvocationResponse -Compress -Depth 3)
    Write-Information $InvocationResponseResponse
  } catch {

    # If something went wrong during invocation, call the invocation error API https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html#runtimes-api-invokeerror
    $InvocationErrorResponse = @{
      errorMessage = $_.Exception.Message
      errorType = $_.Exception.Type
      stackTrace= @( $_.ScriptStackTrace )
    }
    
    $InvocationErrorJson = (ConvertTo-Json -InputObject $InvocationErrorResponse -Compress -Depth 3)
    Write-Error $InvocationErrorJson
    Invoke-RestMethod -Method 'POST' "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$REQUEST_ID/error" -Body $InvocationErrorJson
    
    # Invoke the Close-Handler command if it was defined
    if (Get-Command Close-Handler -ErrorAction SilentlyContinue) {
      Write-Information "Invoking Close-Handler"
      Close-Handler
      Write-Information "Completed Close-Handler"
    }
    exit 1
  }
}

$HasInitialized = $false;
## Initialization Phase
if ($HasInitialized -eq $false) {
  $PreInit = Invoke-PreInitialization
  $PS_HandlerFunction = $PreInit[0]
  $PS_HandlerScriptPath = $PreInit[1]

  # Load the specified handler script using PowerShell's 'source' equivalent
  . $PS_HandlerScriptPath

  $HasInitialized = Invoke-Initialization

  # This is to overcome an interesting side-effect of invoking Connect-ExchangeOnline
  # Reload the handler cript
  . $PS_HandlerScriptPath
}

## Invocation Phase
while(1) {
  # Invoke the AWS Lambda runtime API and get information about the current invocation from it
  # See https://docs.aws.amazon.com/lambda/latest/dg/runtimes-api.html
  $NextInvocationResponse = Invoke-WebRequest "http://$Env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/next"
  
  # Some information is contained in the headers...
  $InvocationInfo = @{
    RequestId = $NextInvocationResponse.Headers['Lambda-Runtime-Aws-Request-Id']
    DeadlineMs = $NextInvocationResponse.Headers['Lambda-Runtime-Deadline-Ms']
    FunctionArn = $NextInvocationResponse.Headers['Lambda-Runtime-Invoked-Function-Arn']
    TraceId = $NextInvocationResponse.Headers['Lambda-Runtime-Trace-Id']
    ClientContext = $NextInvocationResponse.Headers['Lambda-Runtime-Client-Context']
    CognitoIdentity = $NextInvocationResponse.Headers['Lambda-Runtime-Cognito-Identity']
  }

  # And the response body contains the invocation parameters
  $InvocationParameters = ConvertFrom-Json $NextInvocationResponse.Content -AsHashtable

  # Write parameters out to the logs so we can see it easily in cloudwatch
  Write-Information (ConvertTo-Json -InputObject $InvocationInfo -Compress -Depth 3)
  Write-Information (ConvertTo-Json -InputObject $InvocationParameters -Compress -Depth 3)

  # Invoke our the handler function defined by the environment variable with the parmeters and data from the next invocation endpoint
  Invoke-HandlerFunction -PS_HandlerFunction $PS_HandlerFunction -InvocationParameters $InvocationParameters -InvocationInfo $InvocationInfo
}
