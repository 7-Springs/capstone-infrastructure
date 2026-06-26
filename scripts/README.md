# Capstone Direct Deploy

Run the full local verification gate and deploy the pushed `origin/main` backend/frontend to the Lightsail server:

```bash
./capstone-infrastructure/scripts/test-and-deploy.sh
```

The script runs:

- backend build
- backend e2e tests
- frontend unit tests
- frontend production build
- Playwright tests
- server deploy over SSH
- app/API smoke checks

Useful overrides:

```bash
SKIP_PLAYWRIGHT=1 ./capstone-infrastructure/scripts/test-and-deploy.sh
SKIP_DEPLOY=1 ./capstone-infrastructure/scripts/test-and-deploy.sh
DEPLOY_KEY="$HOME/Desktop/LightsailDefaultKey-us-east-1.pem" ./capstone-infrastructure/scripts/test-and-deploy.sh
```

Defaults:

- `DEPLOY_USER=admin`
- `DEPLOY_HOST=18.209.136.92`
- `DEPLOY_KEY=$HOME/Desktop/LightsailDefaultKey-us-east-1.pem`
- `TEST_DATABASE_URL=postgresql://capstone_test:capstone_test@localhost:5432/capstone_test?schema=public`

The Desktop PEM is copied to `/tmp` with `600` permissions before SSH so the original file does not need to be modified.
