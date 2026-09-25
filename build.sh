#!/bin/bash
# WindowTidyy 构建脚本：自动读取 signing.env（不入库）覆盖签名身份。
# 用法: ./build.sh [debug|release|test|install]
set -eo pipefail
cd "$(dirname "$0")"

# 可选签名身份：signing.env 里定义 CODE_SIGN_IDENTITY / DEVELOPMENT_TEAM
# （模板见 signing.env.example；不配置则用 ad-hoc，代价是每次 rebuild 需重新授予辅助功能权限）
if [ -f signing.env ]; then
  source ./signing.env
fi

SIGN_ARGS=""
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  SIGN_ARGS="CODE_SIGN_IDENTITY=\"$CODE_SIGN_IDENTITY\""
fi
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
  SIGN_ARGS="$SIGN_ARGS DEVELOPMENT_TEAM=\"$DEVELOPMENT_TEAM\""
fi

run_xcodebuild() {
  eval xcodebuild -project WindowTidyy.xcodeproj -scheme WindowTidyy "$@" $SIGN_ARGS
}

xcodegen generate

case "${1:-release}" in
  debug)
    run_xcodebuild -configuration Debug build CONFIGURATION_BUILD_DIR="$PWD/build/Debug"
    echo "✅ Debug 构建完成: build/Debug/WindowTidyy.app"
    ;;
  test)
    run_xcodebuild -configuration Debug test CONFIGURATION_BUILD_DIR="$PWD/build/Debug"
    ;;
  release)
    run_xcodebuild -configuration Release build CONFIGURATION_BUILD_DIR="$PWD/build/Release"
    echo "✅ Release 构建完成: build/Release/WindowTidyy.app"
    ;;
  install)
    run_xcodebuild -configuration Release build CONFIGURATION_BUILD_DIR="$PWD/build/Release"
    pkill -x WindowTidyy 2>/dev/null || true
    sleep 1
    rm -rf /Applications/WindowTidyy.app
    cp -R build/Release/WindowTidyy.app /Applications/
    open /Applications/WindowTidyy.app
    echo "✅ 已安装并启动 /Applications/WindowTidyy.app"
    ;;
  *)
    echo "用法: ./build.sh [debug|release|test|install]"
    exit 1
    ;;
esac
