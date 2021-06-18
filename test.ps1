docker build . -t aws-exchange-demo:latest && `
docker run -p 9000:8080 --rm --env-file "./.env.dev" aws-exchange-demo:latest "{ `"foo`": `"bar`" }"