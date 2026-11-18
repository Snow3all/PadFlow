// PadFlow — ใช้จอย PS5 (DualSense) ควบคุมเมาส์บน macOS
import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = Store.shared
    lazy var engine = PadEngine(store: store)
    var item: NSStatusItem!
    var window: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        engine.onChange = { [weak self] in self?.refreshIcon() }
        engine.start()
        refreshIcon()

        let d = UserDefaults.standard
        if !d.bool(forKey: "didShowSettings") || CommandLine.arguments.contains("--settings") {
            d.set(true, forKey: "didShowSettings")
            openSettings()
        }
    }

    /// ดับเบิลคลิกแอปอีกครั้งขณะเปิดอยู่ → เปิดหน้าตั้งค่า
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func refreshIcon() {
        let name = engine.controller == nil ? "gamecontroller" : (engine.enabled ? "gamecontroller.fill" : "pause.circle")
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "PadFlow")
    }

    // MARK: Window

    @objc func openSettings() {
        if window == nil {
            let root = SettingsView().environmentObject(store).environmentObject(engine)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "PadFlow"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 1040, height: 700))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("PadFlowSettings")
            window = w
        }
        engine.uiVisible = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        engine.uiVisible = false
        engine.captureMode = false
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        var status = engine.controllerName.map { tr("Controller: \($0)", "จอย: \($0)") } ?? tr("No controller found", "ยังไม่พบจอย")
        if let b = engine.battery { status += tr(" — Battery \(Int(b * 100))%", " — แบต \(Int(b * 100))%") }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: tr("⚠️ Accessibility permission needed — click to open", "⚠️ ต้องอนุญาต Accessibility — คลิกเพื่อเปิด"), action: #selector(openAX), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())

        let toggle = menu.addItem(withTitle: tr("Enable control", "เปิดใช้งานการควบคุม"), action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = engine.enabled ? .on : .off

        let header = menu.addItem(withTitle: "Preset", action: nil, keyEquivalent: "")
        header.isEnabled = false
        for p in store.presets {
            let i = menu.addItem(withTitle: p.name, action: #selector(choosePreset(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = p.id
            i.state = p.id == store.activeID ? .on : .off
            i.indentationLevel = 1
        }
        let langItem = menu.addItem(withTitle: "Language / ภาษา", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for l in AppLanguage.allCases {
            let i = langMenu.addItem(withTitle: l.nativeName, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = l.rawValue
            i.state = store.language == l ? .on : .off
        }
        langItem.submenu = langMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Open Settings…", "เปิดหน้าตั้งค่า…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        let off = menu.addItem(withTitle: tr("Turn off controller now", "ปิดจอยตอนนี้"), action: #selector(disconnectNow), keyEquivalent: "")
        off.target = self
        off.isEnabled = engine.controller != nil
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Quit PadFlow", "ออกจาก PadFlow"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func toggleEnabled() { engine.enabled.toggle() }
    @objc func chooseLanguage(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let l = AppLanguage(rawValue: raw) { store.language = l }
    }
    @objc func choosePreset(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { store.activeID = id } }
    @objc func disconnectNow() { engine.disconnectNow() }
    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
