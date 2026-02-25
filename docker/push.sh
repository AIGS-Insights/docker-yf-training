while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest) REPO_TAG="latest"; shift ;;
  esac
done

source "$(dirname "$0")/_init.sh"

echo "Tagging Docker image ${CONTAINER_NAME}:${CONTAINER_TAG} as ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}..."
docker tag ${CONTAINER_NAME}:${CONTAINER_TAG} ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}
echo "Logging in to Docker registry ${CONTAINER_REPO} as ${REPO_USERNAME}..."
echo ${REPO_PASSWORD} | docker login --username ${REPO_USERNAME} --password-stdin
echo "Pushing Docker image ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}..."
docker push ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}
echo "Docker image pushed successfully, removing local tag ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}..."
docker rmi ${CONTAINER_REPO}/${CONTAINER_NAME}:${REPO_TAG:-${CONTAINER_TAG}}
echo "Done."