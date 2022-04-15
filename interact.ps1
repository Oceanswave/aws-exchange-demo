#!/usr/bin/env pwsh

docker build . -t aws-exchange-demo:latest && `
docker run -it -p 9000:8080 --rm --env-file "./.env.dev" --entrypoint pwsh aws-exchange-demo:latest 