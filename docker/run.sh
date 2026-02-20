source "$(dirname "$0")/_init.sh"

echo "Running Docker container ${CONTAINER_NAME} from image ${CONTAINER_IMAGE}:${CONTAINER_TAG}..."
docker run --detach --name ${CONTAINER_NAME} --publish ${HOST_PORT}:${CONTAINER_PORT} ${CONTAINER_IMAGE}:${CONTAINER_TAG}