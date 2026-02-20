source "$(dirname "$0")/_init.sh"

echo "Use the following command(s) to run the image from the registry:"
if [[ -z "$CONTAINER_COUNT" ]]; then
  CONTAINER_COUNT=1
fi

for ((i=1; i<=CONTAINER_COUNT; i++)); do
  # Support indexed variables if defined, else fallback to base
  name="${CONTAINER_NAME}$i"
  port=$((HOST_PORT + i))
  echo "docker run --detach --name \"$name\" --publish \"$port:$CONTAINER_PORT\" ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}"
done