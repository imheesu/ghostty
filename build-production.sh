#!/bin/bash
set -e

APP_NAME="Ghosttown"
BUNDLE_NAME="Ghosttown"
BUILD_DIR="macos/build/ReleaseLocal"
APP_PATH="${BUILD_DIR}/${BUNDLE_NAME}.app"
INSTALL_PATH="/Applications/${BUNDLE_NAME}.app"

echo "=== ${APP_NAME} Production Build ==="

# 릴리즈 빌드
echo ">> 빌드 시작 (ReleaseFast)..."
zig build -Doptimize=ReleaseFast

echo ">> 빌드 완료: ${APP_PATH}"

# /Applications에 설치
echo ">> ${INSTALL_PATH} 에 설치..."
rm -rf "${INSTALL_PATH}"
cp -R "${APP_PATH}" "${INSTALL_PATH}"

echo ">> 설치 완료! 다음 앱 재시작 시 새 버전이 적용됩니다."

# --open: 설치 후 바로 실행
# --restart: 실행 중인 앱 종료 후 재실행
if [[ "$1" == "--open" || "$1" == "--restart" ]]; then
    if [[ "$1" == "--restart" ]] && pgrep -x "ghostty" > /dev/null 2>&1; then
        echo ">> 실행 중인 ${APP_NAME} 종료..."
        killall "ghostty" 2>/dev/null || true
        sleep 1
    fi
    echo ">> ${APP_NAME} 실행..."
    open "${INSTALL_PATH}"
fi

echo "=== Done ==="
