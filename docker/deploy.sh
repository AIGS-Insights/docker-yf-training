source "$(dirname "$0")/_init.sh"

if [[ -z "$CONTAINER_COUNT" ]]; then
  CONTAINER_COUNT=1
fi

CONTAINER_IMAGE=${CONTAINER_REPO}/${CONTAINER_IMAGE}
CONTAINER_TAG=${REPO_TAG:-${CONTAINER_TAG}}
echo "Use the following command to run the container ${CONTAINER_NAME} from image ${CONTAINER_IMAGE}:${CONTAINER_TAG}..."
for ((i=1; i<=CONTAINER_COUNT; i++)); do
  YAML_FILE="$GENERATED_DIR/$CONTAINER_NAME$i.yaml"
  CUSTOM_NAME="${CONTAINER_NAME}${i}"
  CUSTOM_PORT=$((${HOST_PORT:-$CONTAINER_PORT} + i))
  sed \
    -e "s|__CONTAINER_GROUP__|${CONTAINER_GROUP}|g" \
    -e "s|__CONTAINER_NAME__|${CUSTOM_NAME}|g" \
    -e "s|__CONTAINER_IMAGE__|${CONTAINER_IMAGE}|g" \
    -e "s|__CONTAINER_TAG__|${CONTAINER_TAG}|g" \
    -e "s|__HOST_PORT__|${CUSTOM_PORT}|g" \
    "$TEMPLATE_FILE" > "$YAML_FILE"
  
  echo "docker-compose --file \"${YAML_FILE}\" up --detach"
  #echo -e "docker run --detach --name \"${CUSTOM_NAME}\" --publish ${CUSTOM_PORT}:${CONTAINER_PORT} \"${CONTAINER_IMAGE}:${CONTAINER_TAG}\""
done