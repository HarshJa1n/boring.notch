#!/bin/bash

# Script to debug why the app won't open
# Usage: ./debug-app.sh /path/to/myBoringNotch.app

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

echo "🔍 Debugging app at: $APP_PATH"
echo ""

echo "📦 App Bundle Structure:"
ls -la "$APP_PATH/Contents/"
echo ""

echo "🔧 Executables:"
ls -la "$APP_PATH/Contents/MacOS/"
echo ""

echo "📋 Info.plist contents:"
if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    plutil -p "$APP_PATH/Contents/Info.plist" | head -20
else
    echo "⚠️  No Info.plist found"
fi
echo ""

echo "🔒 Extended Attributes (quarantine check):"
xattr "$APP_PATH"
echo ""

echo "🔐 Permissions:"
stat -f "%Sp %N" "$APP_PATH/Contents/MacOS/"*
echo ""

echo "🚀 Attempting to run executable directly..."
EXECUTABLE=$(ls "$APP_PATH/Contents/MacOS/" | head -1)
if [ -n "$EXECUTABLE" ]; then
    echo "Running: $APP_PATH/Contents/MacOS/$EXECUTABLE"
    "$APP_PATH/Contents/MacOS/$EXECUTABLE" 2>&1 &
    APP_PID=$!
    echo "App started with PID: $APP_PID"
    sleep 2
    if ps -p $APP_PID > /dev/null; then
        echo "✅ App is running!"
    else
        echo "❌ App crashed or didn't start"
        echo "Check Console.app for crash logs"
    fi
else
    echo "❌ No executable found"
fi
