#!/bin/bash

# Script to properly rename and fix the app
# Usage: ./rename-and-fix-app.sh /path/to/boringNotch.app

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/boringNotch.app"
    exit 1
fi

SOURCE_APP="$1"
NEW_NAME="myBoringNotch"

if [ ! -d "$SOURCE_APP" ]; then
    echo "❌ App not found at: $SOURCE_APP"
    exit 1
fi

echo "📝 Creating ${NEW_NAME}.app..."

# Get the directory where the source app is
APP_DIR=$(dirname "$SOURCE_APP")
NEW_APP_PATH="${APP_DIR}/${NEW_NAME}.app"

# Copy the app
cp -R "$SOURCE_APP" "$NEW_APP_PATH"

echo "🔓 Removing quarantine attributes..."
xattr -cr "$NEW_APP_PATH"

echo "🔧 Fixing permissions..."
chmod -R 755 "$NEW_APP_PATH"

# Make sure the executable is executable
EXECUTABLE_PATH="${NEW_APP_PATH}/Contents/MacOS/boringNotch"
if [ -f "$EXECUTABLE_PATH" ]; then
    chmod +x "$EXECUTABLE_PATH"
    echo "✅ Executable fixed at: $EXECUTABLE_PATH"
fi

echo "✅ App created at: $NEW_APP_PATH"
echo "🚀 Opening app..."

# Try to open the app
open "$NEW_APP_PATH"

echo "🎉 Done! If the app doesn't open, check Console.app for errors."
