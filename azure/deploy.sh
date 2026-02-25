#!/usr/bin/env bash
set -euo pipefail

# Deploy N public Azure Container Apps (${CONTAINER_NAME}1..N) with per-app Azure Files storage.
# Load environment and defaults from _init.sh in script directory
source "$(dirname "$0")/_init.sh"

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
  SAN_APP=$(echo "$CONTAINER_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
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

# Persist state in generated/azure.env
cat > "${GENERATED_DIR}/azure.env" <<EOF
# Generated/updated by deploy.sh
CONTAINER_NAME="${CONTAINER_NAME}"
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

echo "==> Wrote environment file: ./${GENERATED_DIR}/azure.env"

for i in $(seq 1 "$CONTAINER_COUNT"); do
  CONTAINER_INSTANCE="${CONTAINER_NAME}${i}"
  FILE_SHARE="${CONTAINER_INSTANCE}-fileshare"
  STORAGE_LINK="${CONTAINER_INSTANCE}-storage"

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

  YAML_FILE="${GENERATED_DIR}/${CONTAINER_INSTANCE}.yaml"

  CN_ESC=$(escape_sed_replacement "$CONTAINER_INSTANCE")
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
    -e "s|__CONTAINER_INSTANCE__|${CN_ESC}|g" \
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

  if az containerapp show -g "$RESOURCE_GROUP" -n "$CONTAINER_INSTANCE" >/dev/null 2>&1; then
    echo "==> Updating app: $CONTAINER_INSTANCE"
    az containerapp update -g "$RESOURCE_GROUP" -n "$CONTAINER_INSTANCE" --yaml "$YAML_FILE" -o none
  else
    echo "==> Creating app: $CONTAINER_INSTANCE"
    az containerapp create -g "$RESOURCE_GROUP" -n "$CONTAINER_INSTANCE" --yaml "$YAML_FILE" -o none
  fi

done

echo "Done. Generated per-app YAMLs are in ./${GENERATED_DIR}"
