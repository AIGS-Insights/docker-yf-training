#!/bin/bash
# Usage: source ./_init.sh [path_to_env_file]

# Require default .env file from the directory of this script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
DEFAULT_ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$DEFAULT_ENV_FILE" ]]; then
  echo "Error: Default environment file '$DEFAULT_ENV_FILE' not found." >&2
  exit 1
fi

# Support optional additional env file as argument
ADDITIONAL_ENV_FILE="$1"

set -a
. "$DEFAULT_ENV_FILE"
if [[ -n "$ADDITIONAL_ENV_FILE" ]]; then
  if [[ ! -f "$ADDITIONAL_ENV_FILE" ]]; then
    echo "Error: Additional environment file '$ADDITIONAL_ENV_FILE' not found." >&2
    exit 1
  fi
  . "$ADDITIONAL_ENV_FILE"
fi
set +a

# Collect all keys from both env files (if additional provided)
if [[ -n "$ADDITIONAL_ENV_FILE" ]]; then
  SOURC_ENV_FILE=("$DEFAULT_ENV_FILE" "$ADDITIONAL_ENV_FILE")
else
  SOURC_ENV_FILE=("$DEFAULT_ENV_FILE")
fi

# Determine output yaml file path
GENERATED_DIR="$SCRIPT_DIR/../generated"
mkdir -p "$GENERATED_DIR"

TEMPLATE_FILE=${TEMPLATE_FILE:-"$SCRIPT_DIR/template/docker.template.yaml"}
YAML_FILE=${YAML_FILE:-"$GENERATED_DIR/$CONTAINER_NAME.yaml"}