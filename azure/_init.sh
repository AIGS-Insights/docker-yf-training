#!/usr/bin/env bash
# Always resolve default .env relative to this script's directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DEFAULT_ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$DEFAULT_ENV_FILE" ]]; then
  echo "Error: Default environment file '$DEFAULT_ENV_FILE' not found." >&2
  exit 1
fi

# Load default .env
set -a
source "$DEFAULT_ENV_FILE"
echo "==> Loaded .env"
set +a

# Set all default values here (quoted for safety)
CONTAINER_NAME="${CONTAINER_NAME:-yftraining}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-REPLACE_ME}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${CONTAINER_NAME}-resource}"
LOCATION="${LOCATION:-centralus}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-${CONTAINER_NAME}-environment}"
LOGWORKSPACE_NAME="${LOGWORKSPACE_NAME:-${CONTAINER_NAME}-logworkspace}"
CONTAINER_CPU="${CONTAINER_CPU:-2.0}"
CONTAINER_MEMORY="${CONTAINER_MEMORY:-4Gi}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}" # Optional
REPO_USERNAME="${REPO_USERNAME:-}" # Optional
REPO_PASSWORD="${REPO_PASSWORD:-}" # Optional

TEMPLATE_FILE=${TEMPLATE_FILE:-"$SCRIPT_DIR/template/azure.template.yaml"}
GENERATED_DIR=${GENERATED_DIR:-"$SCRIPT_DIR/../generated"}
mkdir -p "$GENERATED_DIR"

if [[ "$CONTAINER_IMAGE" == "REPLACE_ME" ]]; then
  echo "ERROR: Set CONTAINER_IMAGE (in .env or env var)." >&2
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
