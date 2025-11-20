#!/usr/bin/env bash
#
# Build script for Podman (NOT Docker)
# This script builds the remodel-api container image using Podman
#

set -e  # Exit on error

echo "=================================="
echo "Building Remodel API with Podman"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="remodel-api"
IMAGE_TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    echo -e "${RED}❌ Error: podman is not installed${NC}"
    echo "Please install podman first: https://podman.io/getting-started/installation"
    exit 1
fi

echo -e "${GREEN}✓${NC} Podman version: $(podman --version)"

# Build the image
echo ""
echo "Building image: ${FULL_IMAGE}"
echo "This may take a few minutes on first build..."
echo ""

podman build \
    --tag "${FULL_IMAGE}" \
    --file Dockerfile \
    .

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""
    echo "Image: ${FULL_IMAGE}"
    echo ""

    # Show image details
    echo "Image details:"
    podman images "${IMAGE_NAME}"
    echo ""

    # Test the image
    echo "Testing image..."
    echo "Checking WeasyPrint dependencies..."

    if podman run --rm "${FULL_IMAGE}" python -c "import weasyprint; print('✓ WeasyPrint:', weasyprint.VERSION)"; then
        echo -e "${GREEN}✓ WeasyPrint dependencies OK${NC}"
    else
        echo -e "${RED}❌ WeasyPrint test failed!${NC}"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}✓ All tests passed${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Test locally:"
    echo "   podman run -p 8000:8000 -e DATABASE_URL='postgresql://...' ${FULL_IMAGE}"
    echo ""
    echo "2. Export for deployment:"
    echo "   podman save ${FULL_IMAGE} | gzip > ${IMAGE_NAME}-${IMAGE_TAG}.tar.gz"
    echo ""
    echo "3. Copy to server and load:"
    echo "   scp ${IMAGE_NAME}-${IMAGE_TAG}.tar.gz server:/tmp/"
    echo "   ssh server 'podman load < /tmp/${IMAGE_NAME}-${IMAGE_TAG}.tar.gz'"
    echo ""

else
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi
