if (-not(Test-Path -Path ./.aws-lambda-rie -PathType Container)) {
  mkdir -p ./.aws-lambda-rie && `
  curl -Lo ./.aws-lambda-rie/aws-lambda-rie https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie `
  && chmod +x ./.aws-lambda-rie/aws-lambda-rie
}

docker build . -t aws-exchange-demo:latest

# https://docs.aws.amazon.com/lambda/latest/dg/images-test.html
docker run -d -rm --env-file "./.env.dev" -v "$PWD/.aws-lambda-rie:/aws-lambda" -p 9000:8080 `
  --entrypoint /aws-lambda/aws-lambda-rie aws-exchange-demo:latest /usr/bin/pwsh -NoExit -NoLogo -NonInteractive -Command "`$ErrorActionPreference='Stop';`$ProgressPreference='Continue';`$verbosePreference='SilentlyContinue';" ./app.handler.ps1

Write-Host "Waiting for start..."
Start-Sleep 10

Write-Host "Invoking function..."
#curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{}'
Invoke-WebRequest -method "POST" "http://localhost:9000/2015-03-31/functions/function/invocations" -body '{}'
