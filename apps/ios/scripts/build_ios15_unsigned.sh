#!/bin/zsh
# 构建 CrossDesk iOS 15.0 可运行的未签名 IPA。
# 依赖：macOS + Xcode 15+ + xmake（brew install xmake）
# 用法：./apps/ios/scripts/build_ios15_unsigned.sh [/输出目录]
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
IOS_DIR="${SCRIPT_DIR:h}"
REPO_DIR="${IOS_DIR:h:h}"
CONFIG="${CONFIGURATION:-Release}"
OUT_DIR="${1:-${REPO_DIR}/build-ios15}"
DERIVED="${OUT_DIR}/DerivedData"
APP_PATH="${DERIVED}/Build/Products/${CONFIG}-iphoneos/CrossDeskMobile.app"
IPA_PATH="${OUT_DIR}/CrossDeskMobile-iOS15-unsigned.ipa"

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "This script requires macOS (xcodebuild + iOS SDK)."
  exit 64
fi

command -v xcodebuild >/dev/null 2>&1 || { print -u2 "xcodebuild not found: install Xcode."; exit 69; }
if [[ -z "${XMAKE_BIN:-}" ]]; then
  XMAKE_BIN="$(command -v xmake 2>/dev/null || true)"
fi
if [[ -z "${XMAKE_BIN}" ]]; then
  print -u2 "xmake not found: brew install xmake"
  exit 69
fi
export XMAKE_BIN

print "repo    : ${REPO_DIR}"
print "config  : ${CONFIG}"
print "xmake   : ${XMAKE_BIN}"
print "output  : ${OUT_DIR}"

mkdir -p "${OUT_DIR}"
rm -rf "${OUT_DIR}/ipa" "${IPA_PATH}" "${APP_PATH}"

cd "${IOS_DIR}"

xcodebuild \
  -project CrossDeskMobile.xcodeproj \
  -scheme CrossDeskMobile \
  -configuration "${CONFIG}" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  ENABLE_BITCODE=NO \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  print -u2 "app bundle was not produced at ${APP_PATH}"
  exit 66
fi

# 确认 deployment target 真的被降到 15.0，而不是只改了工程文件
BIN="${APP_PATH}/CrossDeskMobile"
print "\n--- LC_BUILD_VERSION ---"
xcrun vtool -show-build "${BIN}" | sed -n '/LC_BUILD_VERSION/,/^$/p'
MINOS="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "${APP_PATH}/Info.plist" 2>/dev/null || true)"
print "Info.plist MinimumOSVersion = ${MINOS:-<absent>}"
if [[ -n "${MINOS}" && "${MINOS}" != 15.0* ]]; then
  print -u2 "unexpected MinimumOSVersion ${MINOS}, expected 15.0"
  exit 65
fi
BIN_MINOS="$(xcrun vtool -show-build "${BIN}" | sed -n 's/^ *minos \([0-9.]*\)$/\1/p' | head -1)"
if [[ "${BIN_MINOS}" != 15.0* ]]; then
  print -u2 "unexpected LC_BUILD_VERSION minos ${BIN_MINOS}, expected 15.0"
  exit 65
fi

STAGE="${OUT_DIR}/ipa"
mkdir -p "${STAGE}/Payload"
cp -R "${APP_PATH}" "${STAGE}/Payload/"
/usr/bin/xattr -cr "${STAGE}/Payload"

(cd "${STAGE}" && /usr/bin/zip -qry "${IPA_PATH}" Payload)

print "\n--- IPA ---"
print "path  : ${IPA_PATH}"
/usr/bin/shasum -a 256 "${IPA_PATH}"
/usr/bin/unzip -l "${IPA_PATH}" | tail -3
