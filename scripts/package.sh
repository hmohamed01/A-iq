#!/bin/bash
# A-IQ Distribution Packaging Script
# Creates a DMG with Applications symlink and styled background

set -e

# Configuration
APP_NAME="A-IQ"
SCHEME="A-IQ"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"
DMG_SIZE="400m"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Clean previous builds
echo_step "Cleaning previous builds..."
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Build release version
echo_step "Building release version..."
cd "$PROJECT_DIR"
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    ONLY_ACTIVE_ARCH=NO \
    | grep -E "(Building|Compiling|Linking|Signing|BUILD|error:|warning:)" || true

# Find the built app
APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo_error "Build failed - app not found at $APP_PATH"
    exit 1
fi

echo_step "Build successful: $APP_PATH"

# Get app version from Info.plist
APP_VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
BUILD_NUMBER=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion 2>/dev/null || echo "1")
echo "  Version: $APP_VERSION ($BUILD_NUMBER)"

# Create background image
echo_step "Creating DMG background image..."
BACKGROUND_PATH="$BUILD_DIR/dmg_background.png"
swift "$PROJECT_DIR/scripts/create_dmg_background.swift" "$BACKGROUND_PATH"

# Create temporary DMG directory
echo_step "Preparing DMG contents..."
DMG_TEMP="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP/.background"

# Copy app and create symlink
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"
cp "$BACKGROUND_PATH" "$DMG_TEMP/.background/background.png"

# Create initial DMG (read-write)
echo_step "Creating DMG..."
DMG_TEMP_PATH="$BUILD_DIR/$APP_NAME-temp.dmg"
rm -f "$DMG_TEMP_PATH"

hdiutil create \
    -srcfolder "$DMG_TEMP" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "$DMG_SIZE" \
    "$DMG_TEMP_PATH"

# Mount the DMG
echo_step "Styling DMG..."
MOUNT_DIR="/Volumes/$VOLUME_NAME"

# Unmount if already mounted
if [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
fi

hdiutil attach "$DMG_TEMP_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

# Apply DMG styling with AppleScript
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 540, 400}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {110, 105}
        set position of item "Applications" of container window to {330, 105}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Wait for Finder to update
sync
sleep 2

# Unmount
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed DMG
echo_step "Compressing DMG..."
DMG_FINAL="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_FINAL"
hdiutil convert "$DMG_TEMP_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"

# Clean up
echo_step "Cleaning up..."
rm -rf "$BUILD_DIR"

# Show result
DMG_SIZE_MB=$(du -h "$DMG_FINAL" | cut -f1)
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  DMG created successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Output: $DMG_FINAL"
echo "  Size:   $DMG_SIZE_MB"
echo "  Version: $APP_VERSION ($BUILD_NUMBER)"
echo ""
echo "To test: open \"$DMG_FINAL\""
echo ""
