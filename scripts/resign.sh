#!/bin/bash
# resign.sh — Pulse 免费（个人）证书重签 + 真机重装脚本
#
# 背景（PLAN.md §2）：
#   无开发者账号时，Xcode 用个人免费证书签名，应用有效期仅 7 天，
#   到期后设备上无法打开（提示"不再可用"）。届时重新运行本脚本即可：
#   用当前 Xcode 已登录的个人证书重新构建、签名并安装。
#
# 使用前准备（一次性）：
#   1. 打开 Xcode → Settings → Accounts → 添加自己的 Apple ID（免费账号即可）。
#   2. project.yml 中 DEVELOPMENT_TEAM 已写入（Team ID 见下），无需手动改。
#   3. watchOS 需在手表上开启开发者模式：
#      手表 设置 → 隐私与安全性 → 开发者模式 → 打开后重启手表。
#   4. 首次安装后需信任开发者证书：
#      iPhone：设置 → 通用 → VPN与设备管理
#      手表：与 iPhone 同步，或手表 设置 → 通用 → 描述文件
#
# 7 天续签流程：
#   到期后连接设备，重新执行本脚本，自动重签并覆盖安装，数据保留
#   （HealthKit 数据在系统健康 App 中，不随 App 卸载丢失）。
#
# 用法：
#   ./scripts/resign.sh phone   # 构建并安装 iOS App
#   ./scripts/resign.sh watch   # 构建并安装 watchOS App（需手表已配对并解锁）
#
# 设备选择：
#   优先读取环境变量 DEVICE_ID（`xcrun devicectl list devices` 的 Identifier）。
#   未设置时按目标自动挑选：watch → Model 为 Watch* 的设备；phone → 其余设备。
#   解析不到则报错并提示设置 DEVICE_ID。
#
# 说明：本脚本仅构建 + 安装；签名由 Xcode 自动完成（CODE_SIGN_STYLE=Automatic）。
# devicectl 用法（实测 Xcode 26）：
#   xcrun devicectl device install app --device <identifier> <app 路径(位置参数)>

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-phone}"

case "$TARGET" in
  phone)
    SCHEME="PulsePhone"
    DESTINATION='generic/platform=iOS'
    PRODUCT_DIR="Debug-iphoneos"
    ;;
  watch)
    SCHEME="PulseWatch"
    PRODUCT_DIR="Debug-watchos"
    # watch 构建必须用具体设备 UDID，否则 provision 不含手表 UDID
    ;;
  *)
    echo "usage: $0 [phone|watch]" >&2
    exit 1
    ;;
esac

DERIVED_DIR="$(pwd)/build"
APP_PATH="$DERIVED_DIR/Build/Products/$PRODUCT_DIR/${SCHEME}.app"

# ── 设备发现 ──
# devicectl identifier (用于 install) vs xctrace UDID (用于 build destination)
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_UDID="${DEVICE_UDID:-}"

if [ -z "$DEVICE_ID" ]; then
  if [ "$TARGET" = "watch" ]; then
    DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
      | awk -F'  +' '$5 ~ /^Watch/ {print $3; exit}')"
  else
    DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
      | awk -F'  +' 'NR > 2 && $3 ~ /-/ && $5 !~ /^Watch/ {print $3; exit}')"
  fi
fi
if [ -z "$DEVICE_ID" ]; then
  echo "no device found; set DEVICE_ID and retry, e.g.:" >&2
  echo "  DEVICE_ID=<uuid> $0 $TARGET" >&2
  echo "list devices: xcrun devicectl list devices" >&2
  exit 1
fi

if [ -z "$DEVICE_UDID" ] && [ "$TARGET" = "watch" ]; then
  DEVICE_UDID="$(xcrun devicectl device info details --device "$DEVICE_ID" 2>/dev/null \
    | awk '/udid:/ {print $2; exit}')"
fi

echo "==> target device: $DEVICE_ID"
if [ -n "$DEVICE_UDID" ]; then
  echo "==> device UDID: $DEVICE_UDID"
fi

# ── 构建 ──
if [ "$TARGET" = "watch" ] && [ -n "$DEVICE_UDID" ]; then
  DESTINATION="platform=watchOS,id=$DEVICE_UDID"
else
  DESTINATION="generic/platform=iOS"
fi

echo "==> build $SCHEME (destination: $DESTINATION)"
xcodebuild \
  -project Pulse.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DIR" \
  -allowProvisioningUpdates \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "missing product: $APP_PATH" >&2
  exit 1
fi

echo "==> install"
if xcrun --find devicectl >/dev/null 2>&1; then
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
else
  # 老版本 Xcode 回退：xcodebuild 直接安装
  xcodebuild -project Pulse.xcodeproj -scheme "$SCHEME" \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath "$DERIVED_DIR" install
fi

echo "==> done. If first install, trust the developer certificate on device."
