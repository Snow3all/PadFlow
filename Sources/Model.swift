// Model.swift — ปุ่ม, คำสั่ง, Preset และที่เก็บข้อมูล
import Foundation
import AppKit
import SwiftUI
import GameController

// MARK: - ภาษา (EN เป็นค่าเริ่มต้น)

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, th
    var id: String { rawValue }
    var nativeName: String { self == .en ? "English" : "ไทย" }
}

enum Lang {
    static var current: AppLanguage =
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .en
}

/// ข้อความสองภาษา: tr("English", "ไทย")
func tr(_ en: String, _ th: String) -> String { Lang.current == .th ? th : en }

// MARK: - ชนิดจอย

enum PadKind: String, Codable, CaseIterable {
    case dualSense, xbox
    var title: String { self == .xbox ? "Xbox Controller" : "DualSense (PS5)" }

    /// ตรวจจากข้อมูลที่ GameController ให้มา
    static func detect(_ c: GCController) -> PadKind {
        if c.extendedGamepad is GCXboxGamepad { return .xbox }
        let info = "\(c.productCategory) \(c.vendorName ?? "")".lowercased()
        return info.contains("xbox") ? .xbox : .dualSense
    }
}

// MARK: - ปุ่มบนจอย

enum PadButton: String, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    case cross, circle, square, triangle
    case l1, r1, l2, r2, l3, r3
    case up, down, left, right
    case create, options, touchpad

    var id: String { rawValue }

    func title(_ kind: PadKind) -> String {
        if kind == .xbox {
            switch self {
            case .cross: return "A"
            case .circle: return "B"
            case .square: return "X"
            case .triangle: return "Y"
            case .l1: return "LB"
            case .r1: return "RB"
            case .l2: return tr("LT (left trigger)", "LT (ไกด้านซ้าย)")
            case .r2: return tr("RT (right trigger)", "RT (ไกด้านขวา)")
            case .l3: return tr("LS (left stick click)", "LS (กดสติ๊กซ้าย)")
            case .r3: return tr("RS (right stick click)", "RS (กดสติ๊กขวา)")
            case .create: return "View"
            case .options: return "Menu"
            case .touchpad: return "Share"
            default: break
            }
        }
        switch self {
        case .cross: return tr("✕ Cross", "✕ กากบาท")
        case .circle: return tr("○ Circle", "○ วงกลม")
        case .square: return tr("□ Square", "□ สี่เหลี่ยม")
        case .triangle: return tr("△ Triangle", "△ สามเหลี่ยม")
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return tr("L2 (left trigger)", "L2 (ไกด้านซ้าย)")
        case .r2: return tr("R2 (right trigger)", "R2 (ไกด้านขวา)")
        case .l3: return tr("L3 (left stick click)", "L3 (กดสติ๊กซ้าย)")
        case .r3: return tr("R3 (right stick click)", "R3 (กดสติ๊กขวา)")
        case .up: return tr("D-pad Up", "D-pad ขึ้น")
        case .down: return tr("D-pad Down", "D-pad ลง")
        case .left: return tr("D-pad Left", "D-pad ซ้าย")
        case .right: return tr("D-pad Right", "D-pad ขวา")
        case .create: return "Create"
        case .options: return "Options"
        case .touchpad: return tr("Touchpad click", "กดทัชแพด")
        }
    }

    func short(_ kind: PadKind) -> String {
        if kind == .xbox {
            switch self {
            case .cross: return "A"
            case .circle: return "B"
            case .square: return "X"
            case .triangle: return "Y"
            case .l1: return "LB"
            case .r1: return "RB"
            case .l2: return "LT"
            case .r2: return "RT"
            case .l3: return "LS"
            case .r3: return "RS"
            case .create: return "View"
            case .options: return "Menu"
            case .touchpad: return "Share"
            default: break
            }
        }
        switch self {
        case .cross: return "✕"
        case .circle: return "○"
        case .square: return "□"
        case .triangle: return "△"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .up: return "▲"
        case .down: return "▼"
        case .left: return "◀"
        case .right: return "▶"
        case .create: return "Create"
        case .options: return "Options"
        case .touchpad: return tr("Touchpad", "ทัชแพด")
        }
    }
}

// MARK: - คำสั่ง

enum ActionGroup: String, CaseIterable, Identifiable {
    case mouse, control, system, media, keys, shortcuts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mouse: return tr("Mouse", "เมาส์")
        case .control: return tr("PadFlow control", "ควบคุม PadFlow")
        case .system: return tr("System", "ระบบ")
        case .media: return tr("Volume, brightness & music", "เสียง แสง และเพลง")
        case .keys: return tr("Keyboard keys", "ปุ่มคีย์บอร์ด")
        case .shortcuts: return tr("Shortcuts", "คีย์ลัด")
        }
    }
    var kinds: [ActionKind] { ActionKind.allCases.filter { $0.group == self } }
}

enum ActionKind: String, Codable, CaseIterable {
    case none
    case leftClick, rightClick, middleClick
    case shiftLayer, precision, boost, toggleEnabled, nextPreset, disconnectPad
    case missionControl, appSwitcher, spotlight, screenshot
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown, playPause, nextTrack, prevTrack
    case escape, enter, space, tab, delete, arrowUp, arrowDown, arrowLeft, arrowRight, pageUp, pageDown
    case back, forward, nextTab, prevTab, newTab, closeTab, zoomIn, zoomOut, copy, paste, undo
    case custom

    var title: String {
        switch self {
        case .none: return tr("Do nothing", "ไม่ทำอะไร")
        case .leftClick: return tr("Left click", "คลิกซ้าย")
        case .rightClick: return tr("Right click", "คลิกขวา")
        case .middleClick: return tr("Middle click", "คลิกกลาง")
        case .shiftLayer: return tr("Shift (hold for 2nd layer)", "ปุ่ม Shift (กดค้างเพื่อใช้ชุดที่ 2)")
        case .precision: return tr("Precision / slow (hold)", "ช้าลง เล็งให้แม่น (กดค้าง)")
        case .boost: return tr("Speed boost (hold)", "เร่งความเร็ว (กดค้าง)")
        case .toggleEnabled: return tr("Toggle control on/off", "เปิด/ปิดการควบคุม")
        case .nextPreset: return tr("Next preset", "สลับไป Preset ถัดไป")
        case .disconnectPad: return tr("Turn off controller", "ปิดจอย")
        case .missionControl: return "Mission Control"
        case .appSwitcher: return tr("App switcher (⌘Tab)", "สลับแอป (⌘Tab)")
        case .spotlight: return "Spotlight (⌘Space)"
        case .screenshot: return tr("Screenshot (⇧⌘4)", "จับภาพหน้าจอ (⇧⌘4)")
        case .volumeUp: return tr("Volume up", "เพิ่มเสียง")
        case .volumeDown: return tr("Volume down", "ลดเสียง")
        case .mute: return tr("Mute", "ปิด/เปิดเสียง")
        case .brightnessUp: return tr("Brightness up", "เพิ่มแสงหน้าจอ")
        case .brightnessDown: return tr("Brightness down", "ลดแสงหน้าจอ")
        case .playPause: return tr("Play / pause", "เล่น/หยุดเพลง")
        case .nextTrack: return tr("Next track", "เพลงถัดไป")
        case .prevTrack: return tr("Previous track", "เพลงก่อนหน้า")
        case .escape: return "Esc"
        case .enter: return "Return"
        case .space: return "Space"
        case .tab: return "Tab"
        case .delete: return "Delete"
        case .arrowUp: return tr("Arrow up", "ลูกศรขึ้น")
        case .arrowDown: return tr("Arrow down", "ลูกศรลง")
        case .arrowLeft: return tr("Arrow left", "ลูกศรซ้าย")
        case .arrowRight: return tr("Arrow right", "ลูกศรขวา")
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .back: return tr("Back (⌘[)", "ย้อนกลับ (⌘[)")
        case .forward: return tr("Forward (⌘])", "ไปข้างหน้า (⌘])")
        case .nextTab: return tr("Next tab (⌃Tab)", "แท็บถัดไป (⌃Tab)")
        case .prevTab: return tr("Previous tab (⌃⇧Tab)", "แท็บก่อนหน้า (⌃⇧Tab)")
        case .newTab: return tr("New tab (⌘T)", "แท็บใหม่ (⌘T)")
        case .closeTab: return tr("Close tab (⌘W)", "ปิดแท็บ (⌘W)")
        case .zoomIn: return tr("Zoom in (⌘+)", "ซูมเข้า (⌘+)")
        case .zoomOut: return tr("Zoom out (⌘−)", "ซูมออก (⌘−)")
        case .copy: return tr("Copy (⌘C)", "คัดลอก (⌘C)")
        case .paste: return tr("Paste (⌘V)", "วาง (⌘V)")
        case .undo: return tr("Undo (⌘Z)", "เลิกทำ (⌘Z)")
        case .custom: return tr("Custom key", "คีย์ที่กำหนดเอง")
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dashed"
        case .leftClick, .rightClick, .middleClick: return "computermouse"
        case .shiftLayer: return "shift"
        case .precision: return "tortoise"
        case .boost: return "hare"
        case .toggleEnabled: return "power"
        case .nextPreset: return "arrow.triangle.2.circlepath"
        case .disconnectPad: return "gamecontroller"
        case .missionControl: return "rectangle.3.group"
        case .appSwitcher: return "square.stack"
        case .spotlight: return "magnifyingglass"
        case .screenshot: return "camera.viewfinder"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .playPause: return "playpause"
        case .nextTrack: return "forward"
        case .prevTrack: return "backward"
        case .arrowUp: return "arrow.up"
        case .arrowDown: return "arrow.down"
        case .arrowLeft: return "arrow.left"
        case .arrowRight: return "arrow.right"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .custom: return "keyboard"
        default: return "command"
        }
    }

    var group: ActionGroup? {
        switch self {
        case .none, .custom: return nil
        case .leftClick, .rightClick, .middleClick: return .mouse
        case .shiftLayer, .precision, .boost, .toggleEnabled, .nextPreset, .disconnectPad: return .control
        case .missionControl, .appSwitcher, .spotlight, .screenshot: return .system
        case .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown, .playPause, .nextTrack, .prevTrack: return .media
        case .escape, .enter, .space, .tab, .delete, .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .pageUp, .pageDown: return .keys
        default: return .shortcuts
        }
    }

    var media: MediaKey? {
        switch self {
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .mute: return .mute
        case .brightnessUp: return .brightnessUp
        case .brightnessDown: return .brightnessDown
        case .playPause: return .play
        case .nextTrack: return .next
        case .prevTrack: return .previous
        default: return nil
        }
    }

    /// กดค้างแล้วรัวหรือไม่
    var repeats: Bool {
        switch self {
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown,
             .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .delete, .pageUp, .pageDown, .zoomIn, .zoomOut:
            return true
        default: return false
        }
    }

    var combo: (CGKeyCode, CGEventFlags)? {
        switch self {
        case .missionControl: return (Key.up, .maskControl)
        case .spotlight: return (Key.space, .maskCommand)
        case .screenshot: return (21, [.maskCommand, .maskShift])
        case .escape: return (Key.escape, [])
        case .enter: return (Key.enter, [])
        case .space: return (Key.space, [])
        case .tab: return (Key.tab, [])
        case .delete: return (Key.delete, [])
        case .arrowUp: return (Key.up, [])
        case .arrowDown: return (Key.down, [])
        case .arrowLeft: return (Key.left, [])
        case .arrowRight: return (Key.right, [])
        case .pageUp: return (116, [])
        case .pageDown: return (121, [])
        case .back: return (33, .maskCommand)
        case .forward: return (30, .maskCommand)
        case .nextTab: return (Key.tab, .maskControl)
        case .prevTab: return (Key.tab, [.maskControl, .maskShift])
        case .newTab: return (17, .maskCommand)
        case .closeTab: return (13, .maskCommand)
        case .zoomIn: return (24, .maskCommand)
        case .zoomOut: return (27, .maskCommand)
        case .copy: return (8, .maskCommand)
        case .paste: return (9, .maskCommand)
        case .undo: return (6, .maskCommand)
        default: return nil
        }
    }
}

struct ButtonAction: Codable, Hashable {
    var kind: ActionKind
    var keyCode: UInt16 = 0
    var flags: UInt64 = 0
    var label: String = ""

    static let none = ButtonAction(kind: .none)
    static func k(_ kind: ActionKind) -> ButtonAction { ButtonAction(kind: kind) }
    static func key(_ code: UInt16, _ label: String, flags: CGEventFlags = []) -> ButtonAction {
        ButtonAction(kind: .custom, keyCode: code, flags: flags.rawValue, label: label)
    }

    var title: String { kind == .custom ? KeyNames.describe(keyCode, flags: CGEventFlags(rawValue: flags), label: label) : kind.title }

    var combo: (CGKeyCode, CGEventFlags)? {
        kind == .custom ? (CGKeyCode(keyCode), CGEventFlags(rawValue: flags)) : kind.combo
    }
}

enum KeyNames {
    static let special: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 116: "Page Up", 121: "Page Down", 115: "Home", 119: "End",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func modifiers(_ f: CGEventFlags) -> String {
        var s = ""
        if f.contains(.maskControl) { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift) { s += "⇧" }
        if f.contains(.maskCommand) { s += "⌘" }
        return s
    }

    static func describe(_ code: UInt16, flags: CGEventFlags, label: String) -> String {
        tr("Key ", "คีย์ ") + modifiers(flags) + (special[code] ?? (label.isEmpty ? "#\(code)" : label))
    }
}

// MARK: - Preset

enum StickMode: String, Codable, CaseIterable, Identifiable {
    case cursor, scroll, arrows, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cursor: return tr("Move cursor", "ขยับเคอร์เซอร์")
        case .scroll: return tr("Scroll", "เลื่อนหน้าจอ (Scroll)")
        case .arrows: return tr("Arrow keys", "ปุ่มลูกศร")
        case .none: return tr("Unused", "ไม่ใช้")
        }
    }
}

struct RGB: Codable, Hashable {
    var r: Double, g: Double, b: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    init(_ c: Color) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .systemBlue
        r = Double(n.redComponent); g = Double(n.greenComponent); b = Double(n.blueComponent)
    }
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var map: [PadButton: ButtonAction]
    var shiftMap: [PadButton: ButtonAction] = [:]
    var leftStick: StickMode = .cursor
    var rightStick: StickMode = .scroll
    var cursorSpeed: Double = 1.0
    var acceleration: Double = 2.2
    var scrollSpeed: Double = 1.0
    var deadzone: Double = 0.12
    var invertScroll = false
    var touchpadCursor = true
    var touchpadSpeed: Double = 1.0
    var light = RGB(r: 0.1, g: 0.4, b: 1.0)

    func action(_ b: PadButton) -> ButtonAction { map[b] ?? .none }
    func shiftAction(_ b: PadButton) -> ButtonAction { shiftMap[b] ?? .none }
    var shiftButton: PadButton? { PadButton.allCases.first { action($0).kind == .shiftLayer } }

    static var standard: Preset {
        Preset(name: tr("Default", "ค่าเริ่มต้น"), map: [
            .cross: .k(.leftClick), .circle: .k(.rightClick), .square: .k(.escape), .triangle: .k(.missionControl),
            .l1: .k(.back), .r1: .k(.forward), .l2: .k(.precision), .r2: .k(.boost),
            .l3: .k(.middleClick), .r3: .k(.none),
            .up: .k(.arrowUp), .down: .k(.arrowDown), .left: .k(.arrowLeft), .right: .k(.arrowRight),
            .create: .k(.shiftLayer), .options: .k(.toggleEnabled), .touchpad: .k(.leftClick),
        ], shiftMap: [
            .up: .k(.volumeUp), .down: .k(.volumeDown), .left: .k(.brightnessDown), .right: .k(.brightnessUp),
            .triangle: .k(.mute), .cross: .k(.playPause), .l1: .k(.prevTab), .r1: .k(.nextTab),
            .options: .k(.nextPreset), .square: .k(.screenshot),
        ])
    }

    static var movie: Preset {
        var p = Preset(name: tr("Movies / YouTube", "ดูหนัง / YouTube"), map: [
            .cross: .k(.space), .circle: .k(.escape), .triangle: .key(3, "F"), .square: .k(.mute),
            .left: .k(.arrowLeft), .right: .k(.arrowRight), .up: .k(.volumeUp), .down: .k(.volumeDown),
            .l1: .k(.prevTrack), .r1: .k(.nextTrack), .l2: .k(.precision), .r2: .k(.boost),
            .l3: .k(.leftClick), .r3: .k(.none),
            .create: .k(.shiftLayer), .options: .k(.toggleEnabled), .touchpad: .k(.leftClick),
        ], shiftMap: [
            .left: .k(.brightnessDown), .right: .k(.brightnessUp), .options: .k(.nextPreset),
        ])
        p.light = RGB(r: 1.0, g: 0.15, b: 0.1)
        return p
    }

    static var presentation: Preset {
        var p = Preset(name: tr("Presentation", "นำเสนองาน"), map: [
            .cross: .k(.arrowRight), .circle: .k(.arrowLeft), .r1: .k(.arrowRight), .l1: .k(.arrowLeft),
            .square: .key(11, "B"), .triangle: .k(.escape),
            .up: .k(.arrowUp), .down: .k(.arrowDown), .left: .k(.arrowLeft), .right: .k(.arrowRight),
            .l2: .k(.precision), .r2: .k(.boost), .l3: .k(.leftClick), .r3: .k(.none),
            .create: .k(.shiftLayer), .options: .k(.toggleEnabled), .touchpad: .k(.leftClick),
        ], shiftMap: [
            .up: .k(.volumeUp), .down: .k(.volumeDown), .options: .k(.nextPreset),
        ])
        p.cursorSpeed = 0.7
        p.light = RGB(r: 0.1, g: 0.9, b: 0.3)
        return p
    }
}

// MARK: - Store

final class Store: ObservableObject {
    static let shared = Store()
    private let d = UserDefaults.standard

    @Published var presets: [Preset] { didSet { save(); onChange?() } }
    @Published var activeID: UUID { didSet { d.set(activeID.uuidString, forKey: "activePreset"); onChange?() } }
    @Published var idleMinutes: Int { didSet { d.set(idleMinutes, forKey: "idleMinutes") } }
    @Published var language: AppLanguage = Lang.current {
        didSet {
            Lang.current = language
            d.set(language.rawValue, forKey: "appLanguage")
            renameBuiltIns()
            onChange?()
        }
    }

    /// เปลี่ยนชื่อ Preset ที่มากับแอปให้ตรงภาษา (ไม่แตะชื่อที่ผู้ใช้ตั้งเอง)
    private func renameBuiltIns() {
        let pairs = [("Default", "ค่าเริ่มต้น"), ("Movies / YouTube", "ดูหนัง / YouTube"), ("Presentation", "นำเสนองาน")]
        for i in presets.indices {
            for (en, th) in pairs where presets[i].name == en || presets[i].name == th {
                presets[i].name = language == .th ? th : en
            }
        }
    }
    var onChange: (() -> Void)?

    private init() {
        var loaded: [Preset] = []
        if let data = d.data(forKey: "presets_v1"), let p = try? JSONDecoder().decode([Preset].self, from: data) { loaded = p }
        if loaded.isEmpty { loaded = [.standard, .movie, .presentation] }
        presets = loaded
        let saved = d.string(forKey: "activePreset").flatMap(UUID.init(uuidString:))
        activeID = loaded.first { $0.id == saved }?.id ?? loaded[0].id
        idleMinutes = d.object(forKey: "idleMinutes") as? Int ?? 15
        renameBuiltIns()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) { d.set(data, forKey: "presets_v1") }
    }

    var active: Preset { presets.first { $0.id == activeID } ?? presets[0] }

    func cycle() {
        guard let i = presets.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = presets[(i + 1) % presets.count].id
    }

    @discardableResult
    func add(_ p: Preset) -> UUID { presets.append(p); return p.id }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard var p = presets.first(where: { $0.id == id }) else { return nil }
        p.id = UUID(); p.name += tr(" (copy)", " (สำเนา)")
        return add(p)
    }

    func delete(_ id: UUID) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        if activeID == id { activeID = presets[0].id }
    }

    func exportPreset(_ id: UUID) {
        guard let p = presets.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(p.name).padmouse.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(p).write(to: url)
    }

    func importPreset() -> UUID? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), var p = try? JSONDecoder().decode(Preset.self, from: data)
        else { return nil }
        p.id = UUID()
        return add(p)
    }
}
