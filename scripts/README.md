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

Run directly on the Lightsail server after cloning all three repos under `~/src`:

```bash
cd ~/src/capstone-infrastructure
LOCAL_DEPLOY=1 ./scripts/test-and-deploy.sh
```

When the script is run on the server and the Desktop PEM is not present, it automatically switches to local deploy mode as long as `~/src/capstone-backend` and `~/src/capstone-frontend` exist.

On a fresh server, install Playwright's Chromium browser and required Linux packages before the Playwright suite:

```bash
LOCAL_DEPLOY=1 PLAYWRIGHT_WITH_DEPS=1 ./scripts/test-and-deploy.sh
```

For a faster deploy when Playwright is temporarily blocked by server browser dependencies:

```bash
LOCAL_DEPLOY=1 SKIP_PLAYWRIGHT=1 ./scripts/test-and-deploy.sh
```

Defaults:

- `DEPLOY_USER=admin`
- `DEPLOY_HOST=98.95.137.137`
- `DEPLOY_KEY=$HOME/Desktop/LightsailDefaultKey-us-east-1.pem`
- `TEST_DATABASE_URL=postgresql://capstone_test:capstone_test@localhost:5432/capstone_test?schema=public`
- `INSTALL_PLAYWRIGHT=1`
- `PLAYWRIGHT_WITH_DEPS=0`

The Desktop PEM is copied to `/tmp` with `600` permissions before SSH so the original file does not need to be modified.
