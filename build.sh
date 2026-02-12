#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
SCHEME="MachOView"
PROJECT="${PROJECT_DIR}/machoview.xcodeproj"
CAPSTONE_DIR="${PROJECT_DIR}/capstone"

usage() {
    echo "Usage: $0 [debug|release|clean]"
    echo "  debug   - Build Debug configuration (default)"
    echo "  release - Build Release configuration"
    echo "  clean   - Clean build artifacts"
    exit 1
}

CONFIG="Debug"
ACTION="build"

case "${1:-debug}" in
    debug)
        CONFIG="Debug"
        ;;
    release)
        CONFIG="Release"
        ;;
    clean)
        ACTION="clean"
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Error: Unknown option '$1'"
        usage
        ;;
esac

if [ "$ACTION" = "clean" ]; then
    echo "Cleaning build artifacts..."
    xcodebuild -project "$PROJECT" \
               -scheme "$SCHEME" \
               clean 2>&1 | tail -5
    rm -rf "$BUILD_DIR"
    echo "Cleaning Capstone..."
    cd "$CAPSTONE_DIR" && make clean >/dev/null 2>&1; rm -f libcapstone.a libcapstone.so* libcapstone.dylib*
    echo "Clean complete."
    exit 0
fi

# Build Capstone separately to avoid Xcode sandbox issues
if [ ! -f "${CAPSTONE_DIR}/libcapstone.a" ]; then
    echo "Building Capstone..."
    cd "$CAPSTONE_DIR"
    CAPSTONE_ARCHS="arm aarch64 x86 powerpc" \
    CAPSTONE_USE_SYS_DYN_MEM=yes \
    CAPSTONE_DIET=no \
    CAPSTONE_X86_REDUCE=no \
    CAPSTONE_STATIC=yes \
    ./make.sh mac-universal
    echo "Capstone build complete."
else
    echo "Capstone already built, skipping. (use '$0 clean' to rebuild)"
fi

echo "Building MachOView ($CONFIG)..."
xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -derivedDataPath "$BUILD_DIR" \
           build 2>&1 | while IFS= read -r line; do
    # Show warnings and errors inline
    if echo "$line" | grep -qE '(warning:|error:|BUILD SUCCEEDED|BUILD FAILED|\*\*)'; then
        echo "$line"
    fi
done

# Check xcodebuild exit status via PIPESTATUS
EXIT_CODE=${PIPESTATUS[0]}
if [ $EXIT_CODE -eq 0 ]; then
    APP_PATH=$(find "$BUILD_DIR" -name "MachOView.app" -type d 2>/dev/null | head -1)
    if [ -n "$APP_PATH" ]; then
        echo ""
        echo "Build output: $APP_PATH"
    fi
    echo "Build succeeded."
else
    echo "Build failed with exit code $EXIT_CODE."
    exit $EXIT_CODE
fi
