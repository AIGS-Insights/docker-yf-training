CACHE=""
CACHE_MSG="enabled"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-cache) CACHE="--no-cache"; CACHE_MSG="disabled"; shift ;;
  esac
done

source "$(dirname "$0")/_init.sh"

echo "Building Docker image ${CONTAINER_IMAGE} with cache ${CACHE_MSG} for app version ${APP_VERSION} build ${APP_BUILD}..."
docker build . ${CACHE} --build-arg APP_VERSION=${APP_VERSION} --build-arg APP_BUILD=${APP_BUILD} --tag ${CONTAINER_IMAGE}:${CONTAINER_TAG}