#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
IMAGE_NAME="gha-runner-yolo"
VERSION=${VERSION:-"2.331.0-yolo-1"}
REGISTRY="0x6a6f6e6e79"

echo -e "${BLUE}🚀 YOLO Runner Release${NC}"
echo ""
echo -e "${BLUE}Image:${NC} ${IMAGE_NAME}"
echo -e "${BLUE}Version:${NC} ${VERSION}"
echo -e "${BLUE}Registry:${NC} ${REGISTRY}"
echo ""

# Check if image exists locally
if ! docker image inspect "${IMAGE_NAME}:latest" > /dev/null 2>&1; then
    echo -e "${RED}❌ Image ${IMAGE_NAME}:latest not found${NC}"
    echo "Run ./build.sh first"
    exit 1
fi

# Tag with version
echo -e "${YELLOW}🏷️  Tagging image...${NC}"
docker tag "${IMAGE_NAME}:latest" "${IMAGE_NAME}:${VERSION}"
echo -e "${GREEN}✅ Tagged as ${IMAGE_NAME}:${VERSION}${NC}"

# Tag for registry
echo -e "${YELLOW}🏷️  Tagging for registry...${NC}"
docker tag "${IMAGE_NAME}:${VERSION}" "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
docker tag "${IMAGE_NAME}:${VERSION}" "${REGISTRY}/${IMAGE_NAME}:latest"

# Push version
echo -e "${YELLOW}📤 Pushing ${REGISTRY}/${IMAGE_NAME}:${VERSION}...${NC}"
docker push "${REGISTRY}/${IMAGE_NAME}:${VERSION}"

# Push latest
echo -e "${YELLOW}📤 Pushing ${REGISTRY}/${IMAGE_NAME}:latest...${NC}"
docker push "${REGISTRY}/${IMAGE_NAME}:latest"

echo ""
echo -e "${GREEN}✅ Pushed to registry!${NC}"
echo ""
echo "Images available at:"
echo "  - ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
echo "  - ${REGISTRY}/${IMAGE_NAME}:latest"

# Save tarball
echo ""
echo -e "${YELLOW}💾 Creating tarball...${NC}"
mkdir -p releases
TARBALL="releases/${IMAGE_NAME}-${VERSION}.tar.gz"
docker save "${IMAGE_NAME}:${VERSION}" | gzip > "${TARBALL}"
SIZE=$(du -h "${TARBALL}" | cut -f1)

echo -e "${GREEN}✅ Saved to ${TARBALL} (${SIZE})${NC}"

echo ""
echo -e "${GREEN}🎉 Release complete!${NC}"
echo ""
echo "Pushed to registry:"
echo "  - ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
echo "  - ${REGISTRY}/${IMAGE_NAME}:latest"
echo ""
echo "Local tarball:"
echo "  - ${TARBALL}"