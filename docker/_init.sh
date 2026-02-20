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

# Determine output env file path
if [[ -n "$ADDITIONAL_ENV_FILE" ]]; then
  GENERATED_DIR="$SCRIPT_DIR/../generated"
  mkdir -p "$GENERATED_DIR"
  ENV_BASENAME=$(basename "$ADDITIONAL_ENV_FILE")
  ENV_FILE="$GENERATED_DIR/$ENV_BASENAME"
else
  ENV_FILE="${ENV_FILE:-$GENERATED_DIR/temp.env}"
fi
> "$ENV_FILE" # Clear the env file before writing to it

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

grep -hv '^#' "${SOURC_ENV_FILE[@]}" | cut -d= -f1 | sort -u | while read -r key; do
  [ -z "$key" ] && continue
  eval "value=\"\$$key\""
  # Wrap value in quotes if it contains a space or special characters (#, $, !, etc.)
  if [[ "$value" =~ [\ \#\$\!] ]]; then
    echo "$key=\"$value\""
  else
    echo "$key=$value"
  fi
done > "$ENV_FILE"

#cat $ENV_FILE # Print the generated env file content for debugging