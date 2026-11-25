#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${(%):-%N}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

APP_NAME="KatanaDI"
BUNDLE_IDENTIFIER="com.oklabs.katanadi"
CONFIGURATION="release"
ARCH="x86_64"
OUTPUT_DIR="$REPO_ROOT/dist"
APP_VERSION="0.1.0"
BUILD_VERSION="1"
APP_ICON_PATH=""

cleanup() {
  [[ -n "${ICON_TEMP_DIR:-}" && -d "$ICON_TEMP_DIR" ]] && rm -rf "$ICON_TEMP_DIR"
}

trap cleanup EXIT

usage() {
  cat <<EOF
Usage: ./scripts/build_app.sh [options]

Options:
  --arch <arm64|x86_64|universal>   Target architecture. Default: x86_64
  --configuration <debug|release>   Swift build configuration. Default: release
  --output-dir <path>               Output directory for the .app bundle. Default: ./dist
  --version <string>                CFBundleShortVersionString. Default: 0.1.0
  --build-number <string>           CFBundleVersion. Default: 1
  --help                            Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --version)
      APP_VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_VERSION="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$ARCH" in
  arm64|x86_64|universal) ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Unsupported configuration: $CONFIGURATION" >&2
    exit 1
    ;;
esac

build_arch() {
  local arch="$1"
  echo "==> Building $APP_NAME for $arch ($CONFIGURATION)"
  swift build -c "$CONFIGURATION" --arch "$arch"
}

binary_path_for_arch() {
  local arch="$1"
  echo "$REPO_ROOT/.build/$arch-apple-macosx/$CONFIGURATION/$APP_NAME"
}

generate_app_icon() {
  command -v swift >/dev/null 2>&1 || return 1
  command -v iconutil >/dev/null 2>&1 || return 1

  ICON_TEMP_DIR="$(mktemp -d)"
  local iconset_path="$ICON_TEMP_DIR/$APP_NAME.iconset"
  local icns_path="$ICON_TEMP_DIR/$APP_NAME.icns"

  swift "$SCRIPT_DIR/generate_app_icon.swift" "$iconset_path"
  iconutil -c icns "$iconset_path" -o "$icns_path"

  echo "$icns_path"
}

create_bundle() {
  local binary_path="$1"
  local bundle_path="$2"

  local contents_path="$bundle_path/Contents"
  local macos_path="$contents_path/MacOS"
  local resources_path="$contents_path/Resources"
  local icon_plist_entry=""

  rm -rf "$bundle_path"
  mkdir -p "$macos_path" "$resources_path"

  cp "$binary_path" "$macos_path/$APP_NAME"

  if [[ -n "$APP_ICON_PATH" && -f "$APP_ICON_PATH" ]]; then
    cp "$APP_ICON_PATH" "$resources_path/$APP_NAME.icns"
    icon_plist_entry=$(cat <<EOF
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
EOF
)
  fi

  cat > "$contents_path/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
${icon_plist_entry}
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>KatanaDI needs microphone access to capture the Katana USB input and route it to the built-in output.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$bundle_path" >/dev/null
  fi
}

mkdir -p "$OUTPUT_DIR"

if APP_ICON_PATH="$(generate_app_icon 2>/dev/null)"; then
  echo "==> Generated app icon"
else
  APP_ICON_PATH=""
  echo "==> Warning: failed to generate app icon, continuing without bundle icon" >&2
fi

if [[ "$ARCH" == "universal" ]]; then
  build_arch "arm64"
  build_arch "x86_64"

  ARM_BINARY="$(binary_path_for_arch arm64)"
  X86_BINARY="$(binary_path_for_arch x86_64)"
  FAT_BINARY="$OUTPUT_DIR/$APP_NAME-universal"
  lipo -create "$ARM_BINARY" "$X86_BINARY" -output "$FAT_BINARY"

  BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME-universal.app"
  create_bundle "$FAT_BINARY" "$BUNDLE_PATH"
  rm -f "$FAT_BINARY"
else
  build_arch "$ARCH"

  BINARY_PATH="$(binary_path_for_arch "$ARCH")"
  BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME-$ARCH.app"
  create_bundle "$BINARY_PATH" "$BUNDLE_PATH"
fi

echo "==> App bundle created:"
echo "$BUNDLE_PATH"
