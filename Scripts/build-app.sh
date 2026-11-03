#!/bin/bash
#
# Builds ChromeProfileManager.app with Swift Package Manager only.
# No Xcode project, no xcodebuild, no Apple Developer account.
#
# Usage:
#   ./Scripts/build-app.sh                 # release build + .app + zip + sha256
#   CPM_VERSION=1.2.3 ./Scripts/build-app.sh
#   CPM_SKIP_ZIP=1 ./Scripts/build-app.sh  # only assemble the .app
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

APP_NAME="ChromeProfileManager"
DISPLAY_NAME="Chrome Profile Manager"
BUNDLE_ID="io.github.chromeprofilemanager"
VERSION="${CPM_VERSION:-1.0.0}"
BUILD_NUMBER="${CPM_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
TARGET_TRIPLE="${CPM_TARGET_TRIPLE:-x86_64-apple-macosx13.0}"
OUTPUT_DIR="${ROOT}/build"
DIST_DIR="${ROOT}/dist"
BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${VERSION}-macOS-x86_64.zip"

echo "==> 环境检查"
swift --version
xcode-select -p
echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-version)"
echo "构建流程仅使用 swift build，不调用 xcodebuild。"

echo "==> 生成图标（如缺失）"
if [ ! -f "Resources/AppIcon.icns" ]; then
    swift Scripts/make-icon.swift Resources/AppIcon.icns
fi

echo "==> 依赖解析"
swift package resolve --disable-sandbox

echo "==> Release 构建（${TARGET_TRIPLE}）"
swift build -c release --disable-sandbox --triple "${TARGET_TRIPLE}"
BIN_DIR="$(swift build -c release --disable-sandbox --triple "${TARGET_TRIPLE}" --show-bin-path)"
BINARY="${BIN_DIR}/${APP_NAME}"

if [ ! -f "${BINARY}" ]; then
    echo "错误：没有找到构建产物 ${BINARY}" >&2
    exit 1
fi

echo "==> 组装 .app Bundle"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

cp "${BINARY}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__BUILD__/${BUILD_NUMBER}/g" \
    -e "s/__BUNDLE_ID__/${BUNDLE_ID}/g" \
    "Resources/Info.plist.in" > "${BUNDLE}/Contents/Info.plist"

plutil -lint "${BUNDLE}/Contents/Info.plist" >/dev/null

echo "==> 架构检查"
ARCHS="$(lipo -archs "${BUNDLE}/Contents/MacOS/${APP_NAME}")"
echo "lipo -archs: ${ARCHS}"
if ! echo "${ARCHS}" | grep -qw "x86_64"; then
    echo "错误：构建产物不包含 x86_64 架构。" >&2
    exit 1
fi

echo "==> 最低系统版本检查"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${BUNDLE}/Contents/Info.plist")"
GUI_FLAG="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${BUNDLE}/Contents/Info.plist")"
echo "LSMinimumSystemVersion = ${MIN_OS}, LSUIElement = ${GUI_FLAG}"
if [ "${GUI_FLAG}" != "true" ]; then
    echo "错误：菜单栏应用需要 LSUIElement=true。" >&2
    exit 1
fi

echo "==> Ad-hoc 签名（不使用开发者证书，不公证）"
codesign --force --sign - --timestamp=none "${BUNDLE}"
codesign --verify --deep --strict "${BUNDLE}" && echo "签名校验通过（ad-hoc）"

echo "==> 打包"
if [ -z "${CPM_SKIP_ZIP:-}" ]; then
    mkdir -p "${DIST_DIR}"
    rm -f "${DIST_DIR}/${ZIP_NAME}" "${DIST_DIR}/${ZIP_NAME}.sha256"
    # --norsrc --noextattr 避免在 ZIP 中产生 __MACOSX 冗余目录；ad-hoc 签名
    # 存放在 Mach-O 内，解压后 codesign 校验仍然通过。
    ditto -c -k --keepParent --norsrc --noextattr "${BUNDLE}" "${DIST_DIR}/${ZIP_NAME}"
    ( cd "${DIST_DIR}" && shasum -a 256 "${ZIP_NAME}" > "${ZIP_NAME}.sha256" )
    echo "ZIP: ${DIST_DIR}/${ZIP_NAME}"
    echo "SHA256: $(cat "${DIST_DIR}/${ZIP_NAME}.sha256")"
fi

echo "==> 完成"
echo "App: ${BUNDLE}"
du -sh "${BUNDLE}" | awk '{print "体积: " $1}'
