#!/bin/bash
set -e

echo "🏗️  Building YOLO Runner..."
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get version from git or default
VERSION=${VERSION:-"2.324.0-yolo-2"}
IMAGE_NAME=${IMAGE_NAME:-"gha-runner-yolo"}

echo -e "${BLUE}Image:${NC} ${IMAGE_NAME}:${VERSION}"
echo -e "${BLUE}Platform:${NC} linux/amd64"
echo ""

# Build the Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build \
    --build-arg TARGETARCH=amd64 \
    --build-arg OS=linux \
    -t ${IMAGE_NAME}:${VERSION} \
    -t ${IMAGE_NAME}:latest-2 \
    .

echo ""
echo -e "${GREEN}✅ Build complete!${NC}"
echo ""
echo "Images created:"
echo "  - ${IMAGE_NAME}:${VERSION}"
echo "  - ${IMAGE_NAME}:latest-2"
echo ""
echo "Next steps:"
echo "  1. Test: docker run --rm ${IMAGE_NAME}:latest-2"
echo "  2. Deploy: docker-compose up -d"
echo "  3. Release: ./release.sh"