#!/bin/bash
#
# 构建 Universal Binary（x86_64 + arm64）的 ChromeProfiles.app，并生成
# ZIP / DMG / SHA256SUMS.txt。
#
# 后端：
#   CPM_BUILD_BACKEND=auto    有完整 Xcode 时用 xcodebuild，否则用 SwiftPM 双架构 + lipo
#   CPM_BUILD_BACKEND=xcode   强制 xcodebuild（CI 使用）
#   CPM_BUILD_BACKEND=swiftpm 强制 SwiftPM（仅命令行工具的环境）
#
# 用法：
#   ./Scripts/build-app.sh
#   CPM_VERSION=1.2.3 ./Scripts/build-app.sh
#   CPM_SKIP_DMG=1 ./Scripts/build-app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

APP_NAME="ChromeProfiles"
DISPLAY_NAME="Chrome Profiles"
BUNDLE_ID="io.github.chromeprofiles"
VERSION="${CPM_VERSION:-1.0.2}"
BUILD_NUMBER="${CPM_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
MIN_MACOS="12.0"
BUILD_DIR="${ROOT}/build"
BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DIST_DIR="${ROOT}/dist"
ZIP_NAME="${APP_NAME}-${VERSION}-universal.zip"
DMG_NAME="${APP_NAME}-${VERSION}-universal.dmg"
BACKEND="${CPM_BUILD_BACKEND:-auto}"

echo "==> 环境检查"
sw_vers
echo "host arch: $(uname -m)"
swift --version
xcode-select -p
echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-version)"
echo "目标架构: x86_64 arm64    最低系统: macOS ${MIN_MACOS}"

if [ "${BACKEND}" = "auto" ]; then
    if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
        BACKEND="xcode"
    else
        BACKEND="swiftpm"
    fi
fi
if [ "${BACKEND}" = "xcode" ] && ! xcodebuild -version >/dev/null 2>&1; then
    echo "错误：要求使用 xcodebuild，但当前没有可用的 Xcode。" >&2
    exit 1
fi
echo "构建后端: ${BACKEND}"

echo "==> 生成图标（如缺失）"
if [ ! -f "Resources/AppIcon.icns" ]; then
    swift Scripts/make-icon.swift Resources/AppIcon.icns
fi

mkdir -p "${BUILD_DIR}"
BINARY=""

build_with_swiftpm() {
    echo "==> SwiftPM 双架构 Release 构建"
    for arch in x86_64 arm64; do
        echo "--- ${arch} (macosx${MIN_MACOS})"
        swift build -c release --disable-sandbox \
            --triple "${arch}-apple-macosx${MIN_MACOS}" \
            -Xlinker -dead_strip \
            -Xswiftc -O
    done

    X86_BIN="${ROOT}/.build/x86_64-apple-macosx/release/${APP_NAME}"
    ARM_BIN="${ROOT}/.build/arm64-apple-macosx/release/${APP_NAME}"
    for candidate in "${X86_BIN}" "${ARM_BIN}"; do
        if [ ! -f "${candidate}" ]; then
            echo "错误：缺少 ${candidate}" >&2
            exit 1
        fi
    done

    BINARY="${BUILD_DIR}/${APP_NAME}-${VERSION}-universal.bin"
    lipo -create -output "${BINARY}" "${X86_BIN}" "${ARM_BIN}"
}

if [ "${BACKEND}" = "xcode" ]; then
    echo "==> Xcode Release 构建（Universal Binary）"
    rm -rf "${BUILD_DIR}/DerivedData"
    if xcodebuild \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        ARCHS="x86_64 arm64" \
        ONLY_ACTIVE_ARCH=NO \
        MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}" \
        SWIFT_OPTIMIZATION_LEVEL=-O \
        SWIFT_VERSION=5 \
        DEAD_CODE_STRIPPING=YES \
        ENABLE_HARDENED_RUNTIME=NO \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build; then

        PRODUCTS="${BUILD_DIR}/DerivedData/Build/Products/Release"
        CANDIDATE="$(find "${PRODUCTS}" -maxdepth 2 -type f -name "${APP_NAME}" | head -1)"
        if [ -n "${CANDIDATE}" ]; then
            BINARY="${CANDIDATE}"
        fi
    fi

    if [ -z "${BINARY}" ]; then
        echo "⚠︎ xcodebuild 未能产出可用产物，回退到 SwiftPM 双架构构建。" >&2
        if [ -n "${CPM_XCODE_STRICT:-}" ]; then
            echo "错误：CPM_XCODE_STRICT 已启用，不回退。" >&2
            exit 1
        fi
        build_with_swiftpm
    fi
else
    build_with_swiftpm
fi

echo "==> 架构与最低系统版本检查"
ARCHS="$(lipo -archs "${BINARY}")"
echo "lipo -archs: ${ARCHS}"
for required in x86_64 arm64; do
    if ! echo "${ARCHS}" | tr ' ' '\n' | grep -qx "${required}"; then
        echo "错误：产物缺少 ${required} 架构。" >&2
        exit 1
    fi
done
vtool -show-build "${BINARY}" | sed 's/^/    /'
if ! vtool -show-build "${BINARY}" | grep -q "minos ${MIN_MACOS}"; then
    echo "错误：最低系统版本不是 macOS ${MIN_MACOS}。" >&2
    exit 1
fi

echo "==> 组装 .app Bundle"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

cp "${BINARY}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod 755 "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__BUILD__/${BUILD_NUMBER}/g" \
    -e "s/__BUNDLE_ID__/${BUNDLE_ID}/g" \
    "Resources/Info.plist.in" > "${BUNDLE}/Contents/Info.plist"

plutil -lint "${BUNDLE}/Contents/Info.plist" >/dev/null

BUNDLE_ARCHS="$(lipo -archs "${BUNDLE}/Contents/MacOS/${APP_NAME}")"
echo "Bundle 内可执行文件架构: ${BUNDLE_ARCHS}"
BUNDLE_MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${BUNDLE}/Contents/Info.plist")"
echo "LSMinimumSystemVersion: ${BUNDLE_MIN_OS}"
[ "${BUNDLE_MIN_OS}" = "${MIN_MACOS}" ] || { echo "错误：Info.plist 最低系统版本不符。" >&2; exit 1; }
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${BUNDLE}/Contents/Info.plist" | grep -qw true \
    || { echo "错误：菜单栏应用需要 LSUIElement=true。" >&2; exit 1; }

echo "==> ad-hoc 签名（不是 Apple Developer ID，也未公证）"
codesign --force --sign - --timestamp=none "${BUNDLE}"
codesign --verify --deep --strict "${BUNDLE}" && echo "签名校验通过（ad-hoc）"

echo "==> 打包分发文件"
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/${ZIP_NAME}" "${DIST_DIR}/${DMG_NAME}" "${DIST_DIR}/SHA256SUMS.txt"

# --norsrc --noextattr 避免产生 __MACOSX 冗余目录；ad-hoc 签名在 Mach-O 内，
# 解压后 codesign 仍可通过。
ditto -c -k --keepParent --norsrc --noextattr "${BUNDLE}" "${DIST_DIR}/${ZIP_NAME}"

if [ -z "${CPM_SKIP_DMG:-}" ]; then
    STAGE="${BUILD_DIR}/dmg-stage"
    rm -rf "${STAGE}"
    mkdir -p "${STAGE}"
    cp -R "${BUNDLE}" "${STAGE}/"
    ln -s /Applications "${STAGE}/Applications"
    hdiutil create \
        -volname "${DISPLAY_NAME}" \
        -srcfolder "${STAGE}" \
        -ov -format UDZO \
        "${DIST_DIR}/${DMG_NAME}" >/dev/null
    rm -rf "${STAGE}"
    hdiutil verify "${DIST_DIR}/${DMG_NAME}" >/dev/null && echo "DMG 校验通过"
fi

(
    cd "${DIST_DIR}"
    FILES=("${ZIP_NAME}")
    [ -f "${DMG_NAME}" ] && FILES+=("${DMG_NAME}")
    shasum -a 256 "${FILES[@]}" > SHA256SUMS.txt
)

echo "==> 完成"
echo "App : ${BUNDLE}（$(du -sh "${BUNDLE}" | cut -f1)）"
echo "ZIP : ${DIST_DIR}/${ZIP_NAME}"
if [ -f "${DIST_DIR}/${DMG_NAME}" ]; then
    echo "DMG : ${DIST_DIR}/${DMG_NAME}"
fi
echo "校验:"
sed 's/^/  /' "${DIST_DIR}/SHA256SUMS.txt"
