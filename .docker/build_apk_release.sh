#!/bin/bash

set -eu

# Git branch of DigiByte DeFi Framework to build
BRANCH=${1:-main}
# Enable screenshots (disabled by default for security, but can be useful during testing)
ALLOW_SCREENSHOTS=${2:-false}

# Build KDF libraries
docker build -f .docker/kdf-android-build.dockerfile . -t digibyte/kdf-android --build-arg KDF_BRANCH=${BRANCH}
# Setup Android SDK
docker build -f .docker/android-sdk.dockerfile . -t digibyte/android-sdk:34
# Prepare coins and other dependencies
docker build -f .docker/android-apk-build.dockerfile . -t digibyte/digibyte-wallet-mobile
# Clean projects won't have a build directory, so create it if it doesn't exist
mkdir -p ./build

FLUTTER_BUILD_COMMAND="flutter pub get && flutter build apk --release"
if [ "$ALLOW_SCREENSHOTS" == "true" ]; then
    FLUTTER_BUILD_COMMAND+=" --dart-define=screenshot=true"
fi

docker run --rm -v ./build:/app/build digibyte/digibyte-wallet-mobile:latest bash -c "$FLUTTER_BUILD_COMMAND"
