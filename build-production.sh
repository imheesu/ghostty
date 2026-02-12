#!/bin/bash
set -e

APP_NAME="Ghosttown"
BUNDLE_NAME="Ghostty"
BUILD_DIR="macos/build/ReleaseLocal"
APP_PATH="${BUILD_DIR}/${BUNDLE_NAME}.app"
INSTALL_PATH="/Applications/${BUNDLE_NAME}.app"

echo "=== ${APP_NAME} Production Build ==="

# 기존 앱이 실행 중이면 종료
if pgrep -x "Ghostty" > /dev/null 2>&1; then
    echo ">> 실행 중인 ${APP_NAME} 종료..."
    killall "Ghostty" 2>/dev/null || true
    sleep 1
fi

# 릴리즈 빌드
echo ">> 빌드 시작 (ReleaseFast)..."
zig build -Doptimize=ReleaseFast

echo ">> 빌드 완료: ${APP_PATH}"

# /Applications에 설치
echo ">> ${INSTALL_PATH} 에 설치..."
rm -rf "${INSTALL_PATH}"
cp -R "${APP_PATH}" "${INSTALL_PATH}"

echo ">> 설치 완료!"

# 실행 여부 확인
if [[ "$1" == "--open" ]]; then
    echo ">> ${APP_NAME} 실행..."
    open "${INSTALL_PATH}"
fi

echo "=== Done ==="
