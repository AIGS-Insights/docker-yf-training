#!/usr/bin/env bash
set -euo pipefail

# Deploy N public Azure Container Apps (${APP_NAME}1..N) with per-app Azure Files storage.
#
# What it does:
#  - Loads ./.env if present.
#  - Creates/uses a Log Analytics workspace.
#  - Creates/updates a Container Apps environment wired to Log Analytics.
#  - Creates/uses a Storage Account and creates one Azure File share per app.
#  - Generates per-app YAMLs under ./generated/ and creates/updates the apps.
#  - Writes resolved state to ./generated/.env (used by destroy.sh).

if [[ -f "./.env" ]]; then
  # shellcheck disable=SC1091
  source ./.env
  echo "==> Loaded .env"
fi

APP_NAME=${APP_NAME:-"yftraining"}
CONTAINER_IMAGE=${CONTAINER_IMAGE:-"REPLACE_ME"}
RESOURCE_GROUP=${RESOURCE_GROUP:-"${APP_NAME}-resource"}
LOCATION=${LOCATION:-"centralus"}

# Environment name (strict)
ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-"${APP_NAME}-environment"}

CONTAINER_COUNT=${CONTAINER_COUNT:-10}
LOGWORKSPACE_NAME=${LOGWORKSPACE_NAME:-"${APP_NAME}-logworkspace"}

# Sizing
CONTAINER_CPU=${CONTAINER_CPU:-2.0}
CONTAINER_MEMORY=${CONTAINER_MEMORY:-"4Gi"}

# Optional: provide an existing storage account name. If empty, one will be generated.
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-""}

# Registry credentials (optional for public images)
REPO_USERNAME=${REPO_USERNAME:-""}
REPO_PASSWORD=${REPO_PASSWORD:-""}

TEMPLATE_FILE=${TEMPLATE_FILE:-"template/app.template.yaml"}
GENERATED_DIR=${GENERATED_DIR:-"generated"}

if [[ "$CONTAINER_IMAGE" == "REPLACE_ME" ]]; then
  echo "ERROR: Set CONTAINER_IMAGE (in .env or env var) to an image that listens on port 8080." >&2
  exit 1
fi

if ! [[ "$CONTAINER_COUNT" =~ ^[0-9]+$ ]] || [[ "$CONTAINER_COUNT" -lt 1 ]]; then
  echo "ERROR: CONTAINER_COUNT must be a positive integer." >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: Template YAML not found: $TEMPLATE_FILE" >&2
  exit 1
fi

# Normalize Docker Hub shorthand (user/repo:tag) -> docker.io/user/repo:tag
if [[ "$CONTAINER_IMAGE" != */* ]]; then
  echo "ERROR: CONTAINER_IMAGE must include at least <repo>/<image>:<tag>" >&2
  exit 1
fi
if [[ "$CONTAINER_IMAGE" != *"."*"/"* ]] && [[ "$CONTAINER_IMAGE" != docker.io/* ]] && [[ "$CONTAINER_IMAGE" != *.azurecr.io/* ]]; then
  CONTAINER_IMAGE="docker.io/${CONTAINER_IMAGE}"
fi

# Determine registry server from image
CONTAINER_REPO=""
if [[ "$CONTAINER_IMAGE" == *.azurecr.io/* ]]; then
  CONTAINER_REPO=$(echo "$CONTAINER_IMAGE" | cut -d/ -f1)
elif [[ "$CONTAINER_IMAGE" == docker.io/* ]]; then
  CONTAINER_REPO="docker.io"
else
  CONTAINER_REPO=$(echo "$CONTAINER_IMAGE" | cut -d/ -f1)
fi

# Providers
az provider register --namespace Microsoft.App --wait >/dev/null
az provider register --namespace Microsoft.OperationalInsights --wait >/dev/null

# Resource group
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none

# Log Analytics workspace
if ! az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$LOGWORKSPACE_NAME" >/dev/null 2>&1; then
  echo "==> Creating Log Analytics workspace: $LOGWORKSPACE_NAME"
  az monitor log-analytics workspace create -g "$RESOURCE_GROUP" -n "$LOGWORKSPACE_NAME" -l "$LOCATION" -o none
else
  echo "==> Log Analytics workspace already exists: $LOGWORKSPACE_NAME"
fi
LOGWORKSPACE_CUSTOMER_ID=$(az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$LOGWORKSPACE_NAME" --query customerId -o tsv)
LOGWORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys -g "$RESOURCE_GROUP" -n "$LOGWORKSPACE_NAME" --query primarySharedKey -o tsv)

# Container Apps environment
if ! az containerapp env show -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" >/dev/null 2>&1; then
  echo "==> Creating Container Apps environment: $ENVIRONMENT_NAME"
  az containerapp env create -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" -l "$LOCATION" \
    --logs-destination log-analytics \
    --logs-workspace-id "$LOGWORKSPACE_CUSTOMER_ID" \
    --logs-workspace-key "$LOGWORKSPACE_KEY" \
    -o none
else
  echo "==> Container Apps environment already exists: $ENVIRONMENT_NAME"
  az containerapp env update -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" \
    --logs-destination log-analytics \
    --logs-workspace-id "$LOGWORKSPACE_CUSTOMER_ID" \
    --logs-workspace-key "$LOGWORKSPACE_KEY" \
    -o none || true
fi
ENVIRONMENT_ID=$(az containerapp env show -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" --query id -o tsv)

# Storage account
if [[ -z "$STORAGE_ACCOUNT" ]]; then
  RAND=$(python3 - <<'PY'
import random, string
print(''.join(random.choice(string.ascii_lowercase+string.digits) for _ in range(8)))
PY
)
  SAN_APP=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  STORAGE_ACCOUNT="${SAN_APP}storage${RAND}"
  STORAGE_ACCOUNT=${STORAGE_ACCOUNT:0:24}
fi

if ! az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >/dev/null 2>&1; then
  echo "==> Creating storage account: $STORAGE_ACCOUNT"
  az storage account create -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" -l "$LOCATION" \
    --kind StorageV2 --sku Standard_LRS --enable-large-file-share -o none
else
  echo "==> Storage account already exists: $STORAGE_ACCOUNT"
fi
STORAGE_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" --query "[0].value" -o tsv)

echo "==> Creating shares and deploying $CONTAINER_COUNT apps..."
mkdir -p "$GENERATED_DIR"

# Escape values for safe use in sed replacement strings.
# Escapes: \\ (backslash), & (replacement token), and | (our delimiter).
escape_sed_replacement() {
  printf "%s" "$1" | sed -e "s/[\\\\&|]/\\\\&/g"
}

# Persist state in generated/.env
cat > "${GENERATED_DIR}/.env" <<EOF
# Generated/updated by deploy.sh
APP_NAME="${APP_NAME}"
RESOURCE_GROUP="${RESOURCE_GROUP}"
LOCATION="${LOCATION}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME}"
CONTAINER_COUNT=${CONTAINER_COUNT}
LOGWORKSPACE_NAME="${LOGWORKSPACE_NAME}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT}"
CONTAINER_IMAGE="${CONTAINER_IMAGE}"
CONTAINER_CPU=${CONTAINER_CPU}
CONTAINER_MEMORY="${CONTAINER_MEMORY}"
CONTAINER_REPO="${CONTAINER_REPO}"
REPO_USERNAME="${REPO_USERNAME}"
REPO_PASSWORD="${REPO_PASSWORD}"
TEMPLATE_FILE="${TEMPLATE_FILE}"
GENERATED_DIR="${GENERATED_DIR}"
EOF

echo "==> Wrote environment file: ./${GENERATED_DIR}/.env"

for i in $(seq 1 "$CONTAINER_COUNT"); do
  CONTAINER_NAME="${APP_NAME}${i}"
  FILE_SHARE="${CONTAINER_NAME}-fileshare"
  STORAGE_LINK="${CONTAINER_NAME}-storage"

  echo "==> Ensuring file share exists: $FILE_SHARE"
  az storage share-rm create -g "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" \
    --name "$FILE_SHARE" --quota 1024 --enabled-protocols SMB -o none

  echo "==> Linking share '$FILE_SHARE' to environment as '$STORAGE_LINK'"
  az containerapp env storage set --access-mode ReadWrite \
    --azure-file-account-name "$STORAGE_ACCOUNT" \
    --azure-file-account-key "$STORAGE_KEY" \
    --azure-file-share-name "$FILE_SHARE" \
    --storage-name "$STORAGE_LINK" \
    --name "$ENVIRONMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" -o none

  YAML_FILE="${GENERATED_DIR}/${CONTAINER_NAME}.yaml"

  CN_ESC=$(escape_sed_replacement "$CONTAINER_NAME")
  LOC_ESC=$(escape_sed_replacement "$LOCATION")
  EID_ESC=$(escape_sed_replacement "$ENVIRONMENT_ID")
  IMG_ESC=$(escape_sed_replacement "$CONTAINER_IMAGE")
  CPU_ESC=$(escape_sed_replacement "$CONTAINER_CPU")
  MEM_ESC=$(escape_sed_replacement "$CONTAINER_MEMORY")
  SL_ESC=$(escape_sed_replacement "$STORAGE_LINK")
  CR_ESC=$(escape_sed_replacement "$CONTAINER_REPO")
  RU_ESC=$(escape_sed_replacement "$REPO_USERNAME")
  RP_ESC=$(escape_sed_replacement "$REPO_PASSWORD")

  sed \
    -e "s|__CONTAINER_NAME__|${CN_ESC}|g" \
    -e "s|__LOCATION__|${LOC_ESC}|g" \
    -e "s|__ENVIRONMENT_ID__|${EID_ESC}|g" \
    -e "s|__CONTAINER_IMAGE__|${IMG_ESC}|g" \
    -e "s|__CONTAINER_CPU__|${CPU_ESC}|g" \
    -e "s|__CONTAINER_MEMORY__|${MEM_ESC}|g" \
    -e "s|__STORAGE_LINK__|${SL_ESC}|g" \
    -e "s|__CONTAINER_REPO__|${CR_ESC}|g" \
    -e "s|__REPO_USERNAME__|${RU_ESC}|g" \
    -e "s|__REPO_PASSWORD__|${RP_ESC}|g" \
    "$TEMPLATE_FILE" > "$YAML_FILE"

  if az containerapp show -g "$RESOURCE_GROUP" -n "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "==> Updating app: $CONTAINER_NAME"
    az containerapp update -g "$RESOURCE_GROUP" -n "$CONTAINER_NAME" --yaml "$YAML_FILE" -o none
  else
    echo "==> Creating app: $CONTAINER_NAME"
    az containerapp create -g "$RESOURCE_GROUP" -n "$CONTAINER_NAME" --yaml "$YAML_FILE" -o none
  fi

done

echo "Done. Generated per-app YAMLs are in ./${GENERATED_DIR}"
