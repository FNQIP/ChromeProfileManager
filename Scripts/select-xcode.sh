#!/bin/bash
#
# 选择一个自带 Swift 6（含 swift-testing）的 Xcode，并把路径打印到 stdout。
#
# 各 GitHub macOS 镜像的默认 Xcode 不同（例如 macos-14 默认 15.4，工具链里没有
# Testing 模块），因此不能假设 /Applications/Xcode.app 一定够新。
#
# 用法：
#   APP="$(Scripts/select-xcode.sh)" && sudo xcode-select -s "$APP"
#   CPM_XCODE_DIR=/tmp/fakeapps Scripts/select-xcode.sh   # 用假目录本地测试
#
set -euo pipefail

XCODE_DIR="${CPM_XCODE_DIR:-/Applications}"

# 读取某个 Xcode 的 Swift 版本横幅，优先直接用工具链里的 swift，
# 再用 DEVELOPER_DIR + xcrun 兜底，避免猜错 shim 路径。
swift_banner() {
    local developer="$1"
    local out=""
    local toolchain_swift="${developer}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"

    if [ -x "${toolchain_swift}" ]; then
        out="$("${toolchain_swift}" --version 2>&1 || true)"
    fi

    case "${out}" in
        *"Swift version"*) ;;
        *) out="$(DEVELOPER_DIR="${developer}" xcrun swift --version 2>&1 || true)" ;;
    esac

    printf '%s' "${out}"
}

candidates=()
for app in "${XCODE_DIR}/Xcode.app" "${XCODE_DIR}"/Xcode*.app; do
    [ -d "${app}" ] || continue
    [ -d "${app}/Contents/Developer" ] || continue

    duplicate=0
    for existing in ${candidates[@]+"${candidates[@]}"}; do
        [ "${existing}" = "${app}" ] && duplicate=1
    done
    [ "${duplicate}" -eq 1 ] && continue

    candidates+=("${app}")
done

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "::error::在 ${XCODE_DIR} 下没有找到任何 Xcode 应用。"
    ls -d "${XCODE_DIR}"/Xcode*.app 2>/dev/null || true
    exit 1
fi

echo "候选 Xcode：${candidates[*]}" >&2

for app in ${candidates[@]+"${candidates[@]}"}; do
    banner="$(swift_banner "${app}/Contents/Developer")"
    echo "  探测 ${app} → ${banner%%$'\n'*}" >&2

    case "${banner}" in
        *"Swift version 6"*)
            printf '%s\n' "${app}"
            exit 0
            ;;
    esac
done

echo "::error::没有找到自带 Swift 6 的 Xcode（单元测试需要 swift-testing）。"
echo "候选：${candidates[*]}" >&2
for app in ${candidates[@]+"${candidates[@]}"}; do
    echo "--- ${app}" >&2
    swift_banner "${app}/Contents/Developer" 2>&1 | head -3 >&2
done
echo "--- 当前 xcode-select" >&2
xcode-select -p >&2 2>&1 || true
swift --version 2>&1 | head -3 >&2 || true
exit 1
