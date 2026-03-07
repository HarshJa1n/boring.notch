#!/bin/bash

# Script to create a DMG for boringNotch
# Usage: ./create-dmg.sh

set -e

APP_NAME="boringNotch"  # This is the Xcode scheme name
OUTPUT_APP_NAME="myBoringNotch"  # What you want to call it
DMG_NAME="${OUTPUT_APP_NAME}-Installer"
BUILD_DIR="./build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "🔨 Building app for release..."

# Archive and export the app
# Using ad-hoc signing (sign with -)
xcodebuild archive \
    -scheme "${APP_NAME}" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual" \
    DEVELOPMENT_TEAM=""

# Export the app
xcodebuild -exportArchive \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    -exportPath "${BUILD_DIR}" \
    -exportOptionsPlist exportOptions.plist || {
        # If export fails, just copy the app from the archive
        echo "⚠️  Export failed, copying app manually..."
        cp -R "${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "${BUILD_DIR}/"
    }

# Check if app exists
if [ ! -d "${APP_PATH}" ]; then
    echo "❌ App not found at ${APP_PATH}"
    exit 1
fi

# Rename the app
echo "📝 Renaming app to ${OUTPUT_APP_NAME}.app..."
RENAMED_APP_PATH="${BUILD_DIR}/${OUTPUT_APP_NAME}.app"
cp -R "${APP_PATH}" "${RENAMED_APP_PATH}"

# Re-sign the app and all frameworks
echo "✍️  Re-signing app and frameworks..."
# Remove quarantine
xattr -cr "${RENAMED_APP_PATH}"

# Sign all frameworks first
if [ -d "${RENAMED_APP_PATH}/Contents/Frameworks" ]; then
    for framework in "${RENAMED_APP_PATH}/Contents/Frameworks"/*.framework; do
        if [ -d "$framework" ]; then
            echo "  Signing: $(basename "$framework")"
            codesign --force --deep --sign - "$framework" 2>/dev/null || true
        fi
    done
    for dylib in "${RENAMED_APP_PATH}/Contents/Frameworks"/*.dylib; do
        if [ -f "$dylib" ]; then
            echo "  Signing: $(basename "$dylib")"
            codesign --force --sign - "$dylib" 2>/dev/null || true
        fi
    done
fi

# Sign the entire app bundle
codesign --force --deep --sign - "${RENAMED_APP_PATH}"
echo "✅ App re-signed successfully"

echo "📦 Creating DMG..."

# Check if create-dmg is installed
if command -v create-dmg &> /dev/null; then
    echo "Using create-dmg for professional DMG..."
    create-dmg \
        --volname "${OUTPUT_APP_NAME}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${OUTPUT_APP_NAME}.app" 175 120 \
        --hide-extension "${OUTPUT_APP_NAME}.app" \
        --app-drop-link 425 120 \
        "${DMG_NAME}.dmg" \
        "${RENAMED_APP_PATH}"
else
    echo "Using hdiutil for basic DMG..."
    # Remove old DMG if exists
    rm -f "${DMG_NAME}.dmg"
    
    # Create DMG
    hdiutil create -volname "${OUTPUT_APP_NAME}" \
        -srcfolder "${RENAMED_APP_PATH}" \
        -ov -format UDZO \
        "${DMG_NAME}.dmg"
fi

echo "✅ DMG created: ${DMG_NAME}.dmg"
echo "📍 Location: $(pwd)/${DMG_NAME}.dmg"

# Clean up
# rm -rf "${BUILD_DIR}"

echo "🎉 Done!"
