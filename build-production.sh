#!/bin/bash
set -e

APP_NAME="Ghostty"
BUNDLE_NAME="Ghostty"
BUILD_DIR="macos/build/ReleaseLocal"
APP_PATH="${BUILD_DIR}/${BUNDLE_NAME}.app"
INSTALL_PATH="/Applications/${BUNDLE_NAME}.app"
FAT_LIB="macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a"

echo "=== ${APP_NAME} Production Build ==="

# ── 1. Zig 빌드 (xcframework만, xcodebuild는 스킵) ──
echo ">> Step 1: Zig 빌드 (xcframework)..."
zig build \
    -Doptimize=ReleaseFast \
    -Dxcframework-target=native \
    -Demit-xcframework=true \
    -Demit-macos-app=false

# ── 2. Xcode 26 libtool alignment workaround ──
# Zig 0.15가 생성하는 .a의 일부 .o가 8바이트 미정렬
# → Xcode 26 libtool이 해당 멤버를 무시
# 해결: libtool에 입력된 모든 .a를 찾아서, 개별 .o로 풀고 재패킹
echo ">> Step 2: xcframework 재패킹 (Xcode 26 alignment fix)..."
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# libtool 입력이었던 모든 .a 파일 찾기 (zig 캐시의 lib*.a)
COUNTER=0
for lib_a in $(find .zig-cache -name "lib*.a" -not -name "libghostty-fat.a" | sort); do
    COUNTER=$((COUNTER + 1))
    DIR="$WORK_DIR/$COUNTER"
    mkdir -p "$DIR"
    (cd "$DIR" && ar x "$OLDPWD/$lib_a" && rm -f __.SYMDEF* && chmod 644 *.o 2>/dev/null) || true
done

# 모든 .o를 하나의 fat lib로 합침
find "$WORK_DIR" -name "*.o" -print0 | xargs -0 libtool -static -o "$FAT_LIB" 2>/dev/null
OBJ_COUNT=$(ar t "$FAT_LIB" | grep -cv SYMDEF)
echo "  $OBJ_COUNT objects in fat lib (from $COUNTER source archives)"

# ── 3. Xcode 빌드 ──
echo ">> Step 3: Xcode 빌드..."
cd macos
xcodebuild -target "$BUNDLE_NAME" -configuration ReleaseLocal -arch arm64 \
    ONLY_ACTIVE_ARCH=YES 2>&1 | tail -5
cd ..

echo ">> 빌드 완료: ${APP_PATH}"

# ── 4. /Applications에 설치 ──
echo ">> ${INSTALL_PATH} 에 설치..."
rm -rf "${INSTALL_PATH}"
cp -R "${APP_PATH}" "${INSTALL_PATH}"
echo ">> 설치 완료!"

# ── 5. 빌드 캐시 정리 ──
echo ">> 빌드 캐시 정리..."
for dir in macos/build/*/; do
    [ "$(basename "$dir")" = "ReleaseLocal" ] && continue
    rm -rf "$dir"
done
rm -rf .zig-cache

# --open / --restart
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
