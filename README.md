# AWS Exchange Demo

## Prequisites
 - Serverless
 - AWS CLI
 - Docker

On Windows this can be installed using [chocolatey](https://chocolatey.org/)
```
choco install serverless awscli docker-desktop
```

On Mac, with homebrew
```
brew install serverless awscli
brew install --cask docker
```

Run this to make sure you're calling AWS using the correct account
```aws sts get-caller-identity```

## Deployment instructions

> **Requirements**: Docker. In order to build images locally and push them to ECR, you need to have Docker installed on your local machine. Please refer to [official documentation](https://docs.docker.com/get-docker/).

In order to deploy your service, run the following command

```
sls deploy
```

## Set up environment variables

For a dev environment, copy .env to .env.dev and supply the values

e.g.

```
AAD_APPID=<some guid here>
AAD_ORG=<yourtenant>.onmicrosoft.com
CERT_PATH=./EXOv2.pfx
CERT_PASSWORD=<certificate password>
```

## Test your service

After successful deployment, you can test your service remotely by using the following command:

```
sls invoke --function aws-exchange-demo
```
## Test Locally

A couple of powershell scripts assist with testing the image locally

Build and test the image by running the startup command
``` pwsh
./test.ps1
```

There is also the ability to test using the [AWS Lambda Runtime Interface Emulator (RIE)](https://docs.aws.amazon.com/lambda/latest/dg/images-test.html)
``` pwsh
./test-rie.ps1
```

Build and start the image in an interactive shell
``` pwsh
./interact.ps1
```