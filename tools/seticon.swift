// ตั้งไอคอนให้ไฟล์/โฟลเดอร์/ดิสก์: seticon <icon.icns> <path>
import AppKit
let a = CommandLine.arguments
guard a.count == 3, let img = NSImage(contentsOfFile: a[1]) else { exit(2) }
exit(NSWorkspace.shared.setIcon(img, forFile: a[2], options: []) ? 0 : 1)
