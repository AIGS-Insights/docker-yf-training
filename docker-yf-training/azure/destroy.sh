#!/usr/bin/env bash
set -euo pipefail

# Destroy resources created by deploy.sh.
#
# Default behaviour:
#   - Deletes the entire resource group (fastest & safest cleanup).
#
# Options:
#   --yes            Skip interactive prompt.
#   --keep-rg        Do NOT delete the resource group. Instead deletes contained resources best-effort.
#   --keep-storage   When used with --keep-rg, keeps the persistent storage (storage account + file shares).
#   --env-file X     Use a specific env file (default: ./generated/.env then ./.env).

YES=false
KEEP_RG=false
KEEP_STORAGE=false
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=true; shift ;;
    --keep-rg) KEEP_RG=true; shift ;;
    --keep-storage) KEEP_STORAGE=true; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./destroy.sh [--yes] [--keep-rg] [--keep-storage] [--env-file PATH]

Reads state from ./generated/.env (preferred) or ./.env and removes created Azure resources.

Modes:
  Default: delete the resource group (everything is removed).
  --keep-rg: best-effort delete resources inside the RG.
  --keep-rg --keep-storage: keep the storage account + file shares, delete everything else.

Examples:
  ./destroy.sh
  ./destroy.sh --yes
  ./destroy.sh --keep-rg --yes
  ./destroy.sh --keep-rg --keep-storage --yes
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$KEEP_STORAGE" == true && "$KEEP_RG" != true ]]; then
  echo "ERROR: --keep-storage requires --keep-rg (storage cannot be kept if the whole resource group is deleted)." >&2
  exit 2
fi

# Load state
if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Env file not found: $ENV_FILE" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  echo "==> Loaded env file: $ENV_FILE"
elif [[ -f "./generated/.env" ]]; then
  # shellcheck disable=SC1091
  source ./generated/.env
  echo "==> Loaded env file: ./generated/.env"
elif [[ -f "./.env" ]]; then
  # shellcheck disable=SC1091
  source ./.env
  echo "==> Loaded env file: ./.env"
else
  echo "ERROR: No env file found. Expected ./generated/.env or ./.env" >&2
  exit 1
fi

APP_NAME=${APP_NAME:-"yf-training"}
RESOURCE_GROUP=${RESOURCE_GROUP:-""}
ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-""}
CONTAINER_COUNT=${CONTAINER_COUNT:-""}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-""}
LOGWORKSPACE_NAME=${LOGWORKSPACE_NAME:-"${APP_NAME}-logworkspace"}

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "ERROR: RESOURCE_GROUP is required in the env file." >&2
  exit 1
fi

if [[ -z "$ENVIRONMENT_NAME" ]]; then
  echo "ERROR: ENVIRONMENT_NAME is required in the env file." >&2
  exit 1
fi

if ! az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "==> Resource group does not exist (nothing to destroy): $RESOURCE_GROUP"
  exit 0
fi

if [[ "$YES" != true ]]; then
  echo "About to destroy Azure resources in resource group: $RESOURCE_GROUP"
  if [[ "$KEEP_RG" == true ]]; then
    if [[ "$KEEP_STORAGE" == true ]]; then
      echo "Mode: keep-rg + keep-storage (apps/env/logs removed; storage is preserved)"
    else
      echo "Mode: keep-rg (best-effort delete resources inside the RG)"
    fi
  else
    echo "Mode: delete resource group (recommended)"
  fi
  read -r -p "Continue? (y/N) " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

if [[ "$KEEP_RG" != true ]]; then
  echo "==> Deleting resource group: $RESOURCE_GROUP"
  az group delete -n "$RESOURCE_GROUP" --yes --no-wait
  echo "==> Delete initiated. It may take several minutes to complete."
  exit 0
fi

# Best-effort delete within the RG.
# Delete apps
if [[ -n "$CONTAINER_COUNT" ]] && [[ "$CONTAINER_COUNT" =~ ^[0-9]+$ ]]; then
  APPS=$(for i in $(seq 1 "$CONTAINER_COUNT"); do echo "${APP_NAME}${i}"; done)
else
  echo "==> CONTAINER_COUNT not set; discovering apps by prefix '${APP_NAME}'"
  APPS=$(az containerapp list -g "$RESOURCE_GROUP" --query "[?starts_with(name, '${APP_NAME}')].name" -o tsv 2>/dev/null || true)
fi

for app in $APPS; do
  echo "==> Deleting container app: $app"
  az containerapp delete -g "$RESOURCE_GROUP" -n "$app" --yes >/dev/null 2>&1 || true

done

# If keeping storage, only remove env storage links (optional) but do NOT delete shares/account.
# Note: removing env storage links is safe; it does not delete the underlying Azure Files share.
for app in $APPS; do
  STORAGE_LINK="${app}-storage"
  echo "==> Removing env storage link (best-effort): $STORAGE_LINK"
  az containerapp env storage remove -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" --storage-name "$STORAGE_LINK" -o none >/dev/null 2>&1 || true

done

if [[ "$KEEP_STORAGE" != true ]]; then
  # Remove file shares and storage account (only if storage account is known)
  if [[ -n "$STORAGE_ACCOUNT" ]]; then
    for app in $APPS; do
      FILE_SHARE="${app}-fileshare"
      echo "==> Deleting file share (best-effort): $FILE_SHARE"
      az storage share-rm delete -g "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$FILE_SHARE" -o none >/dev/null 2>&1 || true
    done

    echo "==> Deleting storage account (best-effort): $STORAGE_ACCOUNT"
    az storage account delete -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" --yes >/dev/null 2>&1 || true
  fi
else
  echo "==> Keeping persistent storage as requested (--keep-storage)."
  if [[ -z "$STORAGE_ACCOUNT" ]]; then
    echo "WARN: STORAGE_ACCOUNT is not set in the env file; storage should still be preserved, but nothing will be deleted." >&2
  else
    echo "==> Preserved storage account: $STORAGE_ACCOUNT"
  fi
fi

# Delete Container Apps environment
echo "==> Deleting Container Apps environment (best-effort): $ENVIRONMENT_NAME"
az containerapp env delete -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" --yes >/dev/null 2>&1 || true

# Delete Log Analytics workspace
echo "==> Deleting Log Analytics workspace (best-effort): $LOGWORKSPACE_NAME"
az monitor log-analytics workspace delete -g "$RESOURCE_GROUP" -n "$LOGWORKSPACE_NAME" --yes >/dev/null 2>&1 || true

echo "==> Done. Remaining resources (if any) can be removed by deleting the resource group:"
echo "    az group delete -n \"$RESOURCE_GROUP\" --yes --no-wait"
