# escape=`
# Use the alpine powershell image
FROM mcr.microsoft.com/powershell:alpine-3.12

# Install dependencies with apk
RUN apk add`
  ca-certificates `
  openssl 

# Set the shell to powershell
SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='SilentlyContinue';"]

WORKDIR /var/task

# Install required Powershell Modules
RUN Install-Module ExchangeOnlineManagement -RequiredVersion 2.0.5 -force
#https://github.com/jborean93/omi
RUN Install-Module PSWSMan -force && Install-WSMan

# Copy PowerShell Scripts
COPY ./scripts/ .

ENTRYPOINT ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='SilentlyContinue';", "./app.handler.ps1"]
