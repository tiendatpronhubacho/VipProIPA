#!/usr/bin/env bash
set -euo pipefail

echo "=== Building unsigned IPA ==="

# 1. Chạy lệnh build (Archive)
xcodebuild -project ThreeOneOSFive.xcodeproj \
           -scheme TienDat \
           -configuration Release \
           -sdk iphoneos \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           build

# 2. Tìm file .app vừa build xong
echo "Finding .app file..."
APP_PATH=$(find ./build/Build/Products/Release-iphoneos -name "*.app" -maxdepth 1 | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find the built .app file!"
    exit 1
fi

echo "Found app at: $APP_PATH"

# 3. Tạo thư mục Payload và copy .app vào
rm -rf Payload
mkdir -p Payload
cp -R "$APP_PATH" Payload/

# 4. Nén thành file IPA
IPA_NAME="TienDat-unsigned.ipa"
echo "Zipping to $IPA_NAME..."
rm -f "$IPA_NAME"
zip -r "$IPA_NAME" Payload > /dev/null
rm -rf Payload

echo "=== Build Successful: $IPA_NAME ==="