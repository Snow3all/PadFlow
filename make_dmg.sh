#!/bin/zsh
# สร้าง dist/PadFlow.dmg แบบลากไปวางที่ Applications
# ใช้: ./make_dmg.sh   (จะ build แอปใหม่ก่อน)
set -e
cd "$(dirname "$0")"

APP_NAME=PadFlow
VOL="$APP_NAME"
OUT="dist/$APP_NAME.dmg"
STAGE="build/dmg-stage"
RW="build/$APP_NAME-rw.dmg"

./build.sh
swiftc -O tools/seticon.swift -o build/seticon -framework AppKit
[[ -f dmg/background.tiff ]] || { swiftc -O tools/dmg_background.swift -o build/dmg_background -framework AppKit && ./build/dmg_background dmg && tiffutil -cathidpicheck dmg/bg.png dmg/bg@2x.png -out dmg/background.tiff; }

# ถอดดิสก์ชื่อเดียวกันที่ค้างอยู่
[[ -d "/Volumes/$VOL" ]] && hdiutil detach "/Volumes/$VOL" -force -quiet || true

rm -rf "$STAGE" "$RW"; mkdir -p "$STAGE/.background" dist
ditto "build/$APP_NAME.app" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp dmg/background.tiff "$STAGE/.background/background.tiff"

hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size 60m "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
MNT="/Volumes/$VOL"

# จัดหน้าต่าง Finder: พื้นหลัง + ตำแหน่งไอคอน (ต้องอนุญาตให้ควบคุม Finder ครั้งแรก)
osascript <<APPLESCRIPT || echo "⚠️  จัดหน้าต่าง Finder ไม่สำเร็จ (ไม่ได้รับอนุญาต) — DMG ยังใช้ได้ แต่ไม่มีพื้นหลัง"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# ไอคอนของดิสก์ (ต้องทำหลังจัดหน้าต่าง เพราะ Finder ลบไฟล์นี้ทิ้ง): .VolumeIcon.icns + flag "มีไอคอนเอง" (kHasCustomIcon) ใน FinderInfo
cp Resources/AppIcon.icns "$MNT/.VolumeIcon.icns"
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$MNT" || echo "⚠️  ตั้งไอคอนดิสก์ไม่สำเร็จ"
chmod -Rf go-w "$MNT" || true
sync
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force -quiet
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -f "$RW"; rm -rf "$STAGE"

# ไอคอนของไฟล์ .dmg เอง
./build/seticon Resources/AppIcon.icns "$OUT" || true

echo "✅ $OUT ($(du -h "$OUT" | cut -f1))"
