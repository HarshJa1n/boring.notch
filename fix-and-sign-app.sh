#!/bin/bash

# Script to fix code signing issues
# Usage: ./fix-and-sign-app.sh /path/to/myBoringNotch.app

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/app.app"
    exit 1
fi

APP_PATH="$1"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at: $APP_PATH"
    exit 1
fi

echo "🔍 Fixing code signing for: $APP_PATH"
echo ""

# Remove quarantine
echo "🔓 Removing quarantine attributes..."
xattr -cr "$APP_PATH"

# Remove existing signatures
echo "🧹 Removing old signatures..."
find "$APP_PATH/Contents" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true

# Sign all frameworks first
echo "✍️  Re-signing frameworks..."
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    for framework in "$APP_PATH/Contents/Frameworks"/*.framework; do
        if [ -d "$framework" ]; then
            echo "  Signing: $(basename "$framework")"
            codesign --force --deep --sign - "$framework" 2>&1 || echo "  ⚠️  Warning: Could not sign $(basename "$framework")"
        fi
    done
fi

# Sign any dylibs
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
    for dylib in "$APP_PATH/Contents/Frameworks"/*.dylib; do
        if [ -f "$dylib" ]; then
            echo "  Signing: $(basename "$dylib")"
            codesign --force --sign - "$dylib" 2>&1 || echo "  ⚠️  Warning: Could not sign $(basename "$dylib")"
        fi
    done
fi

# Sign the main executable
echo "✍️  Re-signing main executable..."
EXECUTABLE=$(find "$APP_PATH/Contents/MacOS" -type f -perm +111 | head -1)
if [ -n "$EXECUTABLE" ]; then
    codesign --force --sign - "$EXECUTABLE"
fi

# Sign the entire app bundle
echo "✍️  Re-signing app bundle..."
codesign --force --deep --sign - "$APP_PATH"

echo ""
echo "✅ Code signing fixed!"
echo ""
echo "🧪 Verifying signature..."
codesign --verify --verbose "$APP_PATH" && echo "✅ Signature valid!" || echo "⚠️  Signature verification failed"

echo ""
echo "🚀 Attempting to launch app..."
open "$APP_PATH"

echo ""
echo "🎉 Done! Check if the app opened successfully."
