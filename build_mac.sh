#!/bin/bash
# Build IPA (không ký - ESign ký lại) NGAY TRÊN MAC, khỏi chờ máy macOS của GitHub.
# Cần cài 1 lần: Xcode (App Store) + XcodeGen (brew install xcodegen).
# Chạy:  cd ~/zalo-luu-tru-ios && ./build_mac.sh
# Ra:    ZaloLuuTru.ipa trong thư mục này + chép vào Google Drive/Dự án iPhone/zalocall nếu Mac có cài Google Drive.
set -euo pipefail
cd "$(dirname "$0")"

echo "== Lấy code mới nhất"
git pull --ff-only

command -v xcodegen >/dev/null || { echo "THIẾU XcodeGen: chạy  brew install xcodegen"; exit 1; }
xcodebuild -version >/dev/null 2>&1 || { echo "THIẾU Xcode (hoặc chưa chọn): cài Xcode từ App Store rồi chạy  sudo xcode-select -s /Applications/Xcode.app"; exit 1; }

PB=$(grep -m1 'MARKETING_VERSION' project.yml | grep -oE '[0-9]+(\.[0-9]+)+')
echo "== Phiên bản $PB"

echo "== Tạo dự án"
xcodegen generate

echo "== Build (không ký)"
rm -rf build Payload ZaloLuuTru.ipa
xcodebuild -project ZaloLuuTru.xcodeproj -scheme ZaloLuuTru -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build | tail -n 25

echo "== Đóng gói IPA"
mkdir Payload
cp -R build/Build/Products/Release-iphoneos/ZaloLuuTru.app Payload/
zip -qry ZaloLuuTru.ipa Payload
rm -rf Payload
ls -la ZaloLuuTru.ipa

# Google Drive cho Mac: ~/Library/CloudStorage/GoogleDrive-<email>/My Drive (bản tiếng Việt: "Drive của tôi")
for DRIVE in "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive" "$HOME"/Library/CloudStorage/GoogleDrive-*/"Drive của tôi"; do
  # chỉ chép vào Drive đã có sẵn thư mục "Dự án iPhone" (Mac có thể đăng nhập nhiều tài khoản Drive)
  if [ -d "$DRIVE/Dự án iPhone" ]; then
    mkdir -p "$DRIVE/Dự án iPhone/ZaloApp"
    cp ZaloLuuTru.ipa "$DRIVE/Dự án iPhone/ZaloApp/ZaloLuuTru_v$PB.ipa"
    cp ZaloLuuTru.ipa "$DRIVE/Dự án iPhone/ZaloApp/ZaloLuuTru.ipa"
    echo "== Đã chép vào $DRIVE/Dự án iPhone/ZaloApp/ZaloLuuTru_v$PB.ipa"

    mkdir -p "$DRIVE/Dự án iPhone/zalocall"
    cp ZaloLuuTru.ipa "$DRIVE/Dự án iPhone/zalocall/ZaloCall_v$PB.ipa"
    cp ZaloLuuTru.ipa "$DRIVE/Dự án iPhone/zalocall/ZaloCall.ipa"
    echo "== Đã chép vào $DRIVE/Dự án iPhone/zalocall/ZaloCall_v$PB.ipa"
  fi
done
echo "== XONG"
