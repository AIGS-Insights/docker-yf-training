# Azure Container Apps – Multi-instance Deploy + Destroy

This repository deploys **N** Azure Container Apps named `${APP_NAME}1..N`, each mounted to its **own Azure Files share**, inside a single Container Apps environment.

## Repository layout

```text
.
├─ deploy.sh
├─ destroy.sh
├─ template/
│  └─ app.template.yaml
└─ generated/
   ├─ .env
   └─ <app>.yaml
```

## Prerequisites

- Azure CLI installed and authenticated (`az login`).
- Azure Container Apps CLI commands available (`az containerapp ...`).

## Configure

Create a `.env` in the repo root (optional, but recommended):

```bash
CONTAINER_IMAGE="docker.io/<user-or-org>/<image>:<tag>"
APP_NAME="yf-training"
CONTAINER_COUNT=10
LOCATION="centralus"
RESOURCE_GROUP="yf-training-resource"
ENVIRONMENT_NAME="yf-training-environment"

CONTAINER_CPU=2.0
CONTAINER_MEMORY="4Gi"

REPO_USERNAME=""
REPO_PASSWORD=""
```

## Deploy

```bash
chmod +x deploy.sh destroy.sh
./deploy.sh
```

## Destroy

### Delete everything (recommended)

```bash
./destroy.sh --yes
```

### Keep the resource group (best-effort cleanup)

```bash
./destroy.sh --keep-rg --yes
```

### Keep persistent storage (Azure Files)

If you want to remove apps/environment/logging **but keep the Azure Files storage** (storage account + shares):

```bash
./destroy.sh --keep-rg --keep-storage --yes
```
