source "$(dirname "$0")/_init.sh"

sed \
  -e "s|__CONTAINER_GROUP__|${CONTAINER_GROUP}|g" \
  -e "s|__CONTAINER_NAME__|${CONTAINER_NAME}|g" \
  -e "s|__CONTAINER_IMAGE__|${CONTAINER_IMAGE}|g" \
  -e "s|__CONTAINER_TAG__|${CONTAINER_TAG}|g" \
  -e "s|__HOST_PORT__|${HOST_PORT}|g" \
  "$TEMPLATE_FILE" > "$YAML_FILE"

echo "Use the following command to run the container ${CONTAINER_NAME} from image ${CONTAINER_IMAGE}:${CONTAINER_TAG}..."
echo "docker-compose --file \"${YAML_FILE}\" up --detach"
docker-compose --file "${YAML_FILE}" up --detach
#echo -e "docker run --detach --name \"${CONTAINER_NAME}\" --publish ${HOST_PORT}:${CONTAINER_PORT} \"${CONTAINER_IMAGE}:${CONTAINER_TAG}\""