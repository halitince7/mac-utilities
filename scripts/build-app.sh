#!/bin/bash

# MacUtilities — birleşik arka plan uygulamasını derler, imzalar, kurar.
# Tek binary, tek izin (Accessibility). sudo GEREKMEZ.

set -e

APP_NAME="MacUtilities"
BUNDLE_ID="com.mathatinlabs.macutilities"
VERSION="1.0"

# Kaynak dizini bul (repo kökü)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT_DIR/src/mac-utilities.swift"
ICON="$ROOT_DIR/assets/AppIcon.icns"

BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YEL='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
warn()  { echo -e "${YEL}⚠ $1${NC}"; }

command -v swiftc >/dev/null || { echo "swiftc yok: xcode-select --install"; exit 1; }

# --- 1. Bundle iskeleti ---
info "Bundle oluşturuluyor..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# --- 2. Derle ---
info "Derleniyor..."
swiftc -O -o "$MACOS_DIR/$APP_NAME" "$SRC" \
    -framework Cocoa -framework Foundation
ok "Derlendi"

# --- 3. İkon ---
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$RES_DIR/AppIcon.icns"
    ok "İkon eklendi"
else
    warn "İkon bulunamadı ($ICON) — ikonsuz devam"
fi

# --- 4. Info.plist ---
cat > "$APP_DIR/Contents/Info.plist" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Mac Utilities</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOL
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"
ok "Info.plist yazıldı"

# --- 5. Ad-hoc imza ---
# (İleride Developer ID: codesign --sign "Developer ID Application: ...")
info "İmzalanıyor (ad-hoc)..."
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR" 2>/dev/null \
    && ok "İmzalandı" || warn "İmzalama atlandı"

# --- 6. Kur (~/Applications) ---
info "Kuruluyor: $INSTALLED_APP"
mkdir -p "$INSTALL_DIR"
# Çalışıyorsa durdur
[[ -f "$PLIST" ]] && launchctl unload "$PLIST" 2>/dev/null || true
rm -rf "$INSTALLED_APP"
cp -R "$APP_DIR" "$INSTALLED_APP"
ok "Kuruldu"

# --- 7. LaunchAgent (tek servis) ---
cat > "$PLIST" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array><string>$INSTALLED_APP/Contents/MacOS/$APP_NAME</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOL
ok "LaunchAgent oluşturuldu"

# --- 8. Başlat ---
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST" 2>/dev/null || true
ok "Servis başlatıldı"

echo
ok "Tamamlandı!"
echo
info "Son adım — TEK izin ver:"
echo "  System Settings → Privacy & Security → Accessibility → MacUtilities'i AÇ"
echo
info "İzni verdiğin an otomatik devreye girer (uygulamayı yeniden başlatmana gerek yok)."
