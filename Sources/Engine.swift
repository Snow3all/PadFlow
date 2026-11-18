// Engine.swift — อ่านจอยแล้วส่งเหตุการณ์เมาส์/คีย์บอร์ดตาม Preset
import AppKit
import GameController
import IOBluetooth

// MARK: - Event posting

enum Key {
    static let left: CGKeyCode = 123, right: CGKeyCode = 124, down: CGKeyCode = 125, up: CGKeyCode = 126
    static let escape: CGKeyCode = 53, enter: CGKeyCode = 36, tab: CGKeyCode = 48
    static let space: CGKeyCode = 49, delete: CGKeyCode = 51, command: CGKeyCode = 55
}

enum MediaKey: Int32 {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case play = 16, next = 17, previous = 18
}

enum Poster {
    static let src = CGEventSource(stateID: .hidSystemState)

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { CGDisplayBounds($0) }
    }

    static func clamp(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        let screens = displayBounds()
        if screens.contains(where: { $0.contains(p) }) { return p }
        let home = screens.first(where: { $0.contains(old) }) ?? screens.first ?? .zero
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1),
                       y: min(max(p.y, home.minY), home.maxY - 1))
    }

    static func mouse(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, clickState: Int64 = 1) {
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: clickState)
        e.post(tap: .cghidEventTap)
    }

    static func scroll(dy: Int32, dx: Int32) {
        CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = [], down: Bool) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    static func tap(_ code: CGKeyCode, flags: CGEventFlags = []) {
        key(code, flags: flags, down: true)
        key(code, flags: flags, down: false)
    }

    static func media(_ k: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (Int(k.rawValue) << 16) | (down ? 0xa00 : 0xb00)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                               timestamp: 0, windowNumber: 0, context: nil,
                               subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Bluetooth

enum PadBluetooth {
    static func connectedPads() -> [IOBluetoothDevice] {
        let all = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return all.filter { d in
            let n = (d.name ?? "").lowercased()
            return d.isConnected() && (n.contains("dualsense") || n.contains("wireless controller") || n.contains("dualshock") || n.contains("xbox"))
        }
    }

    @discardableResult
    static func disconnectAll() -> Bool {
        let pads = connectedPads()
        for p in pads { p.closeConnection() }
        return !pads.isEmpty
    }
}

// MARK: - Engine

struct PressEvent: Equatable { let button: PadButton; let n: Int }

final class PadEngine: ObservableObject {
    let store: Store

    @Published var enabled = true { didSet { updateLight(); if !enabled { releaseAll() }; onChange?() } }
    /// โหมดเลือกปุ่มในหน้าตั้งค่า: รับรู้การกดแต่ไม่ส่งคำสั่ง
    @Published var captureMode = false { didSet { if captureMode { releaseAll() } } }
    @Published private(set) var controllerName: String?
    /// ชนิดจอยที่ต่ออยู่ (หรือที่ต่อครั้งล่าสุด)
    @Published private(set) var padKind: PadKind =
        PadKind(rawValue: UserDefaults.standard.string(forKey: "lastPadKind") ?? "") ?? .dualSense
    @Published private(set) var battery: Float?
    @Published private(set) var charging = false
    @Published private(set) var pressed: Set<PadButton> = []
    @Published private(set) var lastPress: PressEvent?
    @Published private(set) var leftStick = CGPoint.zero
    @Published private(set) var rightStick = CGPoint.zero

    var uiVisible = false
    var onChange: (() -> Void)?

    private(set) var controller: GCController?
    private var timer: Timer?, idleTimer: Timer?
    private var accX = 0.0, accY = 0.0, accSX = 0.0, accSY = 0.0
    private var held: [PadButton: ButtonAction] = [:]
    private var shiftCount = 0
    private var appSwitcherHeld = false
    private var leftDown = false, rightDown = false, middleDown = false
    private var lastClickTime = Date.distantPast, lastClickPos = CGPoint.zero, clickCount: Int64 = 0
    private var lastTouch: CGPoint?
    private var repeatTimers: [String: Timer] = [:]
    private var stickArrows: [String: Set<CGKeyCode>] = [:]
    private var lastActivity = Date()
    private var pressCounter = 0, tickCount = 0

    init(store: Store) { self.store = store }

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            self?.attach(n.object as? GCController)
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as? GCController) === self.controller else { return }
            self.releaseAll()
            self.controller = nil
            self.controllerName = nil
            self.battery = nil
            self.attach(GCController.controllers().first)
        }
        GCController.startWirelessControllerDiscovery {}
        attach(GCController.controllers().first)

        store.onChange = { [weak self] in self?.updateLight(); self?.onChange?() }

        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let it = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.slowTick() }
        RunLoop.main.add(it, forMode: .common)
        idleTimer = it
    }

    // MARK: Connect

    static func input(_ b: PadButton, _ pad: GCExtendedGamepad) -> GCControllerButtonInput? {
        switch b {
        case .cross: return pad.buttonA
        case .circle: return pad.buttonB
        case .square: return pad.buttonX
        case .triangle: return pad.buttonY
        case .l1: return pad.leftShoulder
        case .r1: return pad.rightShoulder
        case .l2: return pad.leftTrigger
        case .r2: return pad.rightTrigger
        case .l3: return pad.leftThumbstickButton
        case .r3: return pad.rightThumbstickButton
        case .up: return pad.dpad.up
        case .down: return pad.dpad.down
        case .left: return pad.dpad.left
        case .right: return pad.dpad.right
        case .create: return pad.buttonOptions
        case .options: return pad.buttonMenu
        case .touchpad: return (pad as? GCDualSenseGamepad)?.touchpadButton ?? (pad as? GCXboxGamepad)?.buttonShare
        }
    }

    private func attach(_ c: GCController?) {
        guard let c, let pad = c.extendedGamepad else { onChange?(); return }
        controller = c
        controllerName = c.vendorName ?? "Controller"
        padKind = PadKind.detect(c)
        UserDefaults.standard.set(padKind.rawValue, forKey: "lastPadKind")
        lastActivity = Date()
        pad.valueChangedHandler = { [weak self] _, element in self?.noteActivity(element) }
        for b in PadButton.allCases {
            Self.input(b, pad)?.pressedChangedHandler = { [weak self] _, _, isDown in self?.handle(b, isDown) }
        }
        updateBattery()
        updateLight()
        onChange?()
    }

    // MARK: Buttons

    private func handle(_ b: PadButton, _ isDown: Bool) {
        lastActivity = Date()
        if isDown {
            pressed.insert(b)
            pressCounter += 1
            lastPress = PressEvent(button: b, n: pressCounter)
        } else {
            pressed.remove(b)
        }

        if isDown {
            guard held[b] == nil, !captureMode else { return }
            let p = store.active
            var a = p.action(b)
            if shiftCount > 0, a.kind != .shiftLayer, p.shiftAction(b).kind != .none { a = p.shiftAction(b) }
            guard enabled || a.kind == .toggleEnabled else { return }
            held[b] = a
            perform(a, down: true, id: b.rawValue)
        } else if let a = held.removeValue(forKey: b) {
            perform(a, down: false, id: b.rawValue)
        }
    }

    private func perform(_ a: ButtonAction, down: Bool, id: String) {
        switch a.kind {
        case .none, .precision, .boost:
            break
        case .leftClick: leftButton(down)
        case .rightClick: mouseButton(.right, down)
        case .middleClick: mouseButton(.center, down)
        case .shiftLayer: shiftCount = max(0, shiftCount + (down ? 1 : -1))
        case .toggleEnabled: if down { enabled.toggle() }
        case .nextPreset: if down { store.cycle() }
        case .disconnectPad: if down { disconnectNow() }
        case .appSwitcher:
            if down {
                appSwitcherHeld = true
                Poster.key(Key.command, flags: .maskCommand, down: true)
                startRepeat(id, initial: 0.6, every: 0.6) { Poster.tap(Key.tab, flags: .maskCommand) }
            } else {
                stopRepeat(id)
                appSwitcherHeld = false
                Poster.key(Key.command, flags: [], down: false)
            }
        default:
            if let m = a.kind.media {
                if down {
                    if a.kind.repeats { startRepeat(id, initial: 0.4, every: 0.12) { Poster.media(m) } }
                    else { Poster.media(m) }
                } else { stopRepeat(id) }
            } else if let (code, flags) = a.combo {
                let f = appSwitcherHeld ? flags.union(.maskCommand) : flags
                if down {
                    if a.kind.repeats || (a.kind == .custom && flags.isEmpty) {
                        startRepeat(id, initial: 0.4, every: 0.05) { Poster.key(code, flags: f, down: true) }
                    } else {
                        Poster.key(code, flags: f, down: true)
                    }
                } else {
                    stopRepeat(id)
                    Poster.key(code, flags: f, down: false)
                }
            }
        }
    }

    private func startRepeat(_ id: String, initial: TimeInterval, every: TimeInterval, _ fire: @escaping () -> Void) {
        stopRepeat(id)
        fire()
        let start = Timer(timeInterval: initial, repeats: false) { [weak self] _ in
            let r = Timer(timeInterval: every, repeats: true) { _ in fire() }
            RunLoop.main.add(r, forMode: .common)
            self?.repeatTimers[id] = r
        }
        RunLoop.main.add(start, forMode: .common)
        repeatTimers[id] = start
    }

    private func stopRepeat(_ id: String) {
        repeatTimers.removeValue(forKey: id)?.invalidate()
    }

    private func leftButton(_ down: Bool) {
        let p = Poster.cursor
        if down {
            guard !leftDown else { return }
            let now = Date()
            let near = hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < 6
            clickCount = (now.timeIntervalSince(lastClickTime) < NSEvent.doubleClickInterval && near) ? clickCount + 1 : 1
            lastClickTime = now; lastClickPos = p
            leftDown = true
            Poster.mouse(.leftMouseDown, at: p, button: .left, clickState: clickCount)
        } else if leftDown {
            leftDown = false
            Poster.mouse(.leftMouseUp, at: p, button: .left, clickState: clickCount)
        }
    }

    private func mouseButton(_ b: CGMouseButton, _ down: Bool) {
        let p = Poster.cursor
        if b == .right {
            guard down != rightDown else { return }
            rightDown = down
            Poster.mouse(down ? .rightMouseDown : .rightMouseUp, at: p, button: .right)
        } else {
            guard down != middleDown else { return }
            middleDown = down
            Poster.mouse(down ? .otherMouseDown : .otherMouseUp, at: p, button: .center)
        }
    }

    func releaseAll() {
        for (b, a) in held { perform(a, down: false, id: b.rawValue) }
        held.removeAll()
        shiftCount = 0
        repeatTimers.values.forEach { $0.invalidate() }
        repeatTimers.removeAll()
        for (_, keys) in stickArrows { keys.forEach { Poster.key($0, down: false) } }
        stickArrows.removeAll()
        let p = Poster.cursor
        if leftDown { leftDown = false; Poster.mouse(.leftMouseUp, at: p, button: .left) }
        if rightDown { rightDown = false; Poster.mouse(.rightMouseUp, at: p, button: .right) }
        if middleDown { middleDown = false; Poster.mouse(.otherMouseUp, at: p, button: .center) }
    }

    // MARK: Idle / battery

    private func noteActivity(_ element: GCControllerElement) {
        if let s = element as? GCControllerDirectionPad {
            if hypot(s.xAxis.value, s.yAxis.value) > 0.25 { lastActivity = Date() }
        } else if let b = element as? GCControllerButtonInput {
            if b.value > 0.1 { lastActivity = Date() }
        } else {
            lastActivity = Date()
        }
    }

    private func slowTick() {
        updateBattery()
        let mins = store.idleMinutes
        guard mins > 0, controller != nil,
              Date().timeIntervalSince(lastActivity) > Double(mins) * 60 else { return }
        lastActivity = Date()
        disconnectNow()
    }

    func disconnectNow() {
        releaseAll()
        PadBluetooth.disconnectAll()
    }

    private func updateBattery() {
        guard let bat = controller?.battery else { battery = nil; return }
        battery = bat.batteryLevel
        charging = bat.batteryState == .charging
    }

    func updateLight() {
        guard let light = controller?.light else { return }
        let c = store.active.light
        light.color = enabled ? GCColor(red: Float(c.r), green: Float(c.g), blue: Float(c.b))
                              : GCColor(red: 0.4, green: 0.05, blue: 0.05)
    }

    // MARK: Analog

    private func curve(_ v: Float, _ p: Preset) -> Double {
        let a = Double(abs(v))
        guard a > p.deadzone else { return 0 }
        let n = min((a - p.deadzone) / (1 - p.deadzone), 1)
        return (v < 0 ? -1 : 1) * pow(n, p.acceleration)
    }

    private func tick() {
        guard let pad = controller?.extendedGamepad else { return }
        let l = CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value))
        let r = CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value), y: CGFloat(pad.rightThumbstick.yAxis.value))

        tickCount += 1
        if uiVisible && tickCount % 4 == 0 {
            if l != leftStick { leftStick = l }
            if r != rightStick { rightStick = r }
        }
        guard enabled, !captureMode else { return }
        let p = store.active

        var mult = p.cursorSpeed
        for (b, a) in p.map where a.kind == .precision || a.kind == .boost {
            let v = Double(Self.input(b, pad)?.value ?? 0)
            mult *= a.kind == .boost ? 1 + v * 1.8 : 1 - v * 0.75
        }

        var dx = 0.0, dy = 0.0, sx = 0.0, sy = 0.0
        for (id, stick, mode) in [("L", pad.leftThumbstick, p.leftStick), ("R", pad.rightThumbstick, p.rightStick)] {
            let cx = curve(stick.xAxis.value, p), cy = curve(stick.yAxis.value, p)
            switch mode {
            case .cursor:
                dx += cx * 16 * mult
                dy -= cy * 16 * mult
            case .scroll:
                let inv: Double = p.invertScroll ? -1 : 1
                sy += cy * 22 * p.scrollSpeed * inv
                sx -= cx * 22 * p.scrollSpeed * inv
            case .arrows:
                stickToArrows(id, x: stick.xAxis.value, y: stick.yAxis.value)
            case .none:
                break
            }
            if mode != .arrows, let keys = stickArrows.removeValue(forKey: id) {
                keys.forEach { stopRepeat("stick\(id)-\($0)"); Poster.key($0, down: false) }
            }
        }

        if let ds = pad as? GCDualSenseGamepad, p.touchpadCursor {
            let t = CGPoint(x: CGFloat(ds.touchpadPrimary.xAxis.value), y: CGFloat(ds.touchpadPrimary.yAxis.value))
            let touching = t.x != 0 || t.y != 0
            if touching, let last = lastTouch, hypot(t.x - last.x, t.y - last.y) < 0.5 {
                dx += Double(t.x - last.x) * 700 * p.touchpadSpeed
                dy -= Double(t.y - last.y) * 700 * p.touchpadSpeed
            }
            lastTouch = touching ? t : nil
        }

        accX += dx; accY += dy
        let mx = accX.rounded(.towardZero), my = accY.rounded(.towardZero)
        if mx != 0 || my != 0 {
            accX -= mx; accY -= my
            let old = Poster.cursor
            let pt = Poster.clamp(CGPoint(x: old.x + mx, y: old.y + my), from: old)
            let type: CGEventType = leftDown ? .leftMouseDragged : rightDown ? .rightMouseDragged : middleDown ? .otherMouseDragged : .mouseMoved
            let btn: CGMouseButton = leftDown ? .left : rightDown ? .right : middleDown ? .center : .left
            Poster.mouse(type, at: pt, button: btn)
        }

        accSY += sy; accSX += sx
        let iy = accSY.rounded(.towardZero), ix = accSX.rounded(.towardZero)
        if iy != 0 || ix != 0 {
            accSY -= iy; accSX -= ix
            Poster.scroll(dy: Int32(iy), dx: Int32(ix))
        }
    }

    private func stickToArrows(_ id: String, x: Float, y: Float) {
        var want: Set<CGKeyCode> = []
        if x > 0.5 { want.insert(Key.right) } else if x < -0.5 { want.insert(Key.left) }
        if y > 0.5 { want.insert(Key.up) } else if y < -0.5 { want.insert(Key.down) }
        let have = stickArrows[id] ?? []
        for k in have.subtracting(want) { stopRepeat("stick\(id)-\(k)"); Poster.key(k, down: false) }
        for k in want.subtracting(have) {
            startRepeat("stick\(id)-\(k)", initial: 0.35, every: 0.07) { Poster.key(k, down: true) }
        }
        stickArrows[id] = want
    }
}
