# escape=`
ARG CS_PROJECT_FILENAME='exchange_cli.csproj'

## Use a multi-stage build to reduce final image size.
FROM mcr.microsoft.com/dotnet/aspnet:5.0-alpine AS base
WORKDIR /app
EXPOSE 443

## Build stage
FROM mcr.microsoft.com/dotnet/sdk:5.0-alpine AS build
WORKDIR /src
COPY ["./src/${CS_PROJECT_FILENAME}", ""]
RUN dotnet restore "./${CS_PROJECT_FILENAME}"
COPY ./src/ .
WORKDIR "/src/."
RUN dotnet build "${CS_PROJECT_FILENAME}" -c Release -o /app/build

## Publish stage - note the -r parameter so that .net core need not be installed in the final image. linux-musl-x64 is needed for alpine
FROM build AS publish
RUN dotnet publish "${CS_PROJECT_FILENAME}" -c Release -r linux-musl-x64 -o /app/publish

## Final Stage
FROM mcr.microsoft.com/powershell:alpine-3.12
WORKDIR /app

# Set the shell to powershell
SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='SilentlyContinue';"]

# Install required Powershell Modules
RUN Install-Module ExchangeOnlineManagement -RequiredVersion 2.0.5 -Scope AllUsers -Force
# https://github.com/jborean93/omi
RUN Install-Module PSWSMan -Scope AllUsers -Force && Install-WSMan

# Copy the built app
COPY --from=publish /app/publish ./exchange_cli/

# Copy PowerShell Scripts
COPY ./scripts/ .

ENTRYPOINT ["pwsh", "-NoExit", "-NoLogo", "-NonInteractive", "./bootstrap.ps1"]
