// SettingsUI.swift — หน้าต่างตั้งค่า PadFlow
import SwiftUI
import AppKit
import ServiceManagement
import Combine

enum SidebarItem: Hashable { case general, preset(UUID) }

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: PadEngine
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            switch selection {
            case .preset(let id):
                if let b = binding(id) { PresetEditor(preset: b).id(id) }
                else { Text(tr("Select a preset on the left", "เลือก Preset ทางซ้าย")).foregroundStyle(.secondary) }
            case .general, .none:
                GeneralView()
            }
        }
        .id(store.language)   // เปลี่ยนภาษา → วาดหน้าใหม่ทั้งหมด
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { if selection == nil { selection = .preset(store.activeID) } }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ConnectionRow().tag(SidebarItem.general)
            }
            Section("Preset") {
                ForEach(store.presets) { p in
                    HStack(spacing: 8) {
                        Circle().fill(p.light.color).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.black.opacity(0.15)))
                        Text(p.name).lineLimit(1)
                        Spacer()
                        if p.id == store.activeID {
                            Text(tr("Active", "ใช้อยู่")).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .tag(SidebarItem.preset(p.id))
                    .contextMenu {
                        Button(tr("Use this preset", "ใช้ Preset นี้")) { store.activeID = p.id }
                        Button(tr("Duplicate", "ทำสำเนา")) { if let n = store.duplicate(p.id) { selection = .preset(n) } }
                        Button(tr("Export…", "ส่งออก…")) { store.exportPreset(p.id) }
                        Divider()
                        Button(tr("Delete", "ลบ"), role: .destructive) { delete(p.id) }.disabled(store.presets.count < 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 2) {
                Button { selection = .preset(store.add(.standard.renamed(tr("New preset", "Preset ใหม่")))) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 22)
                }.help(tr("New preset", "สร้าง Preset ใหม่"))
                Button { if case .preset(let id) = selection { delete(id) } } label: {
                    Image(systemName: "minus").frame(width: 24, height: 22)
                }.help(tr("Delete preset", "ลบ Preset")).disabled(!canDelete)
                Button { if case .preset(let id) = selection, let n = store.duplicate(id) { selection = .preset(n) } } label: {
                    Image(systemName: "plus.square.on.square").frame(width: 24, height: 22)
                }.help(tr("Duplicate", "ทำสำเนา")).disabled(!isPresetSelected)
                Spacer()
                Menu {
                    Button(tr("Import preset…", "นำเข้า Preset…")) { if let n = store.importPreset() { selection = .preset(n) } }
                    Button(tr("Export this preset…", "ส่งออก Preset นี้…")) { if case .preset(let id) = selection { store.exportPreset(id) } }
                        .disabled(!isPresetSelected)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var isPresetSelected: Bool { if case .preset = selection { return true }; return false }
    private var canDelete: Bool { isPresetSelected && store.presets.count > 1 }

    private func delete(_ id: UUID) {
        let a = NSAlert()
        a.messageText = tr("Delete this preset?", "ลบ Preset นี้?")
        a.informativeText = store.presets.first { $0.id == id }?.name ?? ""
        a.addButton(withTitle: tr("Delete", "ลบ")); a.addButton(withTitle: tr("Cancel", "ยกเลิก"))
        a.buttons[0].hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        store.delete(id)
        selection = .preset(store.activeID)
    }

    private func binding(_ id: UUID) -> Binding<Preset>? {
        guard let initial = store.presets.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.presets.first { $0.id == id } ?? initial },
            set: { new in if let i = store.presets.firstIndex(where: { $0.id == id }) { store.presets[i] = new } }
        )
    }
}

extension Preset {
    func renamed(_ n: String) -> Preset { var p = self; p.name = n; return p }
}

struct ConnectionRow: View {
    @EnvironmentObject var engine: PadEngine
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.controllerName == nil ? "gamecontroller" : "gamecontroller.fill")
                .font(.title3)
                .foregroundStyle(engine.controllerName == nil ? Color.secondary : (engine.enabled ? Color.accentColor : Color.orange))
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.controllerName ?? tr("No controller found", "ยังไม่พบจอย")).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
    private var subtitle: String {
        guard engine.controllerName != nil else { return tr("General settings", "ตั้งค่าทั่วไป") }
        var s = engine.enabled ? tr("Active", "กำลังทำงาน") : tr("Paused", "หยุดชั่วคราว")
        if let b = engine.battery { s += tr(" · Battery \(Int(b * 100))%", " · แบต \(Int(b * 100))%") + (engine.charging ? " ⚡︎" : "") }
        return s
    }
}

// MARK: - Preset editor

struct PresetEditor: View {
    @Binding var preset: Preset
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: PadEngine
    @State private var tab = 0
    @State private var renaming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // ชื่อ Preset: แสดงเป็นข้อความ แก้ได้เมื่อกดปุ่มดินสอ/ดับเบิลคลิก
                // (เดิมเป็นช่องพิมพ์ที่ได้โฟกัสทันที → ปุ่มที่กดเผลอเปลี่ยนชื่อ)
                if renaming {
                    TextField(tr("Preset name", "ชื่อ Preset"), text: $preset.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: 360)
                        .focused($nameFocused)
                        .onSubmit { renaming = false }
                        .onAppear { nameFocused = true }
                        .onChange(of: nameFocused) { f in if !f { renaming = false } }
                    Button(tr("Done", "เสร็จ")) { renaming = false }
                } else {
                    Text(preset.name.isEmpty ? tr("Untitled", "ไม่มีชื่อ") : preset.name)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                        .onTapGesture(count: 2) { renaming = true }
                    Button { renaming = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help(tr("Rename", "เปลี่ยนชื่อ"))
                }
                Spacer()
                ColorPicker(tr("Light bar color", "สีไฟจอย"), selection: Binding(get: { preset.light.color }, set: { preset.light = RGB($0) }),
                            supportsOpacity: false)
                    .fixedSize()
                if preset.id == store.activeID {
                    Label(tr("In use", "กำลังใช้งาน"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout.weight(.medium))
                } else {
                    Button(tr("Use this preset", "ใช้ Preset นี้")) { store.activeID = preset.id }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)

            Picker("", selection: $tab) {
                Text(tr("Buttons", "ปุ่ม")).tag(0)
                Text(tr("Sticks & speed", "สติ๊กและความเร็ว")).tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320)
            .padding(.bottom, 12)

            Divider()

            if tab == 0 { ButtonsTab(preset: $preset) } else { SticksTab(preset: $preset) }
        }
        .navigationTitle(preset.name)
    }
}

// MARK: - Buttons tab

struct ButtonsTab: View {
    @Binding var preset: Preset
    @EnvironmentObject var engine: PadEngine
    @State private var selected: PadButton = .cross
    @State private var hovered: PadButton?

    private var hoverText: String {
        if let h = hovered { return "\(h.title(engine.padKind)) — \(preset.action(h).title)" }
        return tr("Drag to rotate · Double-click to reset · Click a button to select", "ลากเพื่อหมุน · ดับเบิลคลิกเพื่อรีเซ็ตมุม · คลิกปุ่มเพื่อเลือก")
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Controller3DView(kind: engine.padKind, preset: preset, selected: $selected, hovered: $hovered,
                                 pressed: engine.pressed, left: engine.leftStick, right: engine.rightStick)
                    .id(engine.padKind)   // เปลี่ยนชนิดจอย → สร้างฉากใหม่
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        Text(hoverText)
                            .font(.callout)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 8)
                            .animation(.easeOut(duration: 0.15), value: hovered)
                    }
                Toggle(isOn: $engine.captureMode) {
                    Text(tr("Press a controller button to select it (actions paused)", "กดปุ่มบนจอยเพื่อเลือกปุ่มที่จะตั้งค่า (ปิดคำสั่งชั่วคราว)"))
                }
                .toggleStyle(.switch).controlSize(.small)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(selected.title(engine.padKind)).font(.title3.bold())

                    GroupBox {
                        ActionPicker(action: binding(for: selected, shift: false))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    } label: { Text(tr("Normal press", "กดปกติ")) }

                    GroupBox {
                        if preset.action(selected).kind == .shiftLayer {
                            Text(tr("This button is the Shift button", "ปุ่มนี้เป็นปุ่ม Shift อยู่แล้ว")).foregroundStyle(.secondary).padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ActionPicker(action: binding(for: selected, shift: true))
                                Text(shiftHint).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                        }
                    } label: { Text(shiftLabel) }

                    Divider().padding(.vertical, 4)
                    Text(tr("All buttons", "ปุ่มทั้งหมด")).font(.headline)

                    VStack(spacing: 0) {
                        ForEach(PadButton.allCases) { b in
                            Button { selected = b } label: { MappingRow(button: b, preset: preset, selected: b == selected, kind: engine.padKind) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .frame(width: 340)
        }
        .onChange(of: engine.lastPress) { e in if let e { selected = e.button } }
    }

    private var shiftLabel: String {
        if let s = preset.shiftButton { return tr("While holding \(s.short(engine.padKind))", "กดพร้อม \(s.short(engine.padKind)) ค้าง") }
        return tr("While holding Shift", "กดพร้อมปุ่ม Shift")
    }

    private var shiftHint: String {
        preset.shiftButton == nil
            ? tr("No Shift button yet — assign “Shift” to any button first", "ยังไม่มีปุ่ม Shift — ตั้งปุ่มใดก็ได้เป็น “ปุ่ม Shift” ก่อน")
            : tr("“Do nothing” falls back to the normal press action", "ถ้าเลือก “ไม่ทำอะไร” จะใช้คำสั่งของการกดปกติแทน")
    }

    private func binding(for b: PadButton, shift: Bool) -> Binding<ButtonAction> {
        Binding(
            get: { shift ? preset.shiftAction(b) : preset.action(b) },
            set: { if shift { preset.shiftMap[b] = $0 } else { preset.map[b] = $0 } }
        )
    }
}

struct MappingRow: View {
    let button: PadButton
    let preset: Preset
    let selected: Bool
    let kind: PadKind
    var body: some View {
        let a = preset.action(button), s = preset.shiftAction(button)
        HStack(spacing: 8) {
            Text(button.short(kind)).font(.system(.callout, design: .rounded).weight(.semibold))
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title).foregroundStyle(a.kind == .none ? .secondary : .primary).lineLimit(1)
                if s.kind != .none && a.kind != .shiftLayer {
                    Text("⇧ " + s.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.16) : .clear))
        .contentShape(Rectangle())
    }
}

// MARK: - Action picker

struct ActionPicker: View {
    @Binding var action: ButtonAction
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Button { action = .none } label: { Label(ActionKind.none.title, systemImage: ActionKind.none.icon) }
                ForEach(ActionGroup.allCases) { g in
                    Section(g.title) {
                        ForEach(g.kinds, id: \.self) { k in
                            Button { action = .k(k) } label: { Label(k.title, systemImage: k.icon) }
                        }
                    }
                }
                Section {
                    Button { recording = true } label: { Label(tr("Record custom key…", "กำหนดคีย์เอง…"), systemImage: "keyboard") }
                }
            } label: {
                Label(action.title, systemImage: action.kind.icon)
            }
            .fixedSize(horizontal: false, vertical: true)

            if recording {
                KeyRecorder(onDone: { a in
                    if let a { action = a }
                    recording = false
                })
            }
        }
    }
}

struct KeyRecorder: View {
    var onDone: (ButtonAction?) -> Void
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(Color.accentColor)
            Text(tr("Press a key or shortcut on the keyboard…", "กดคีย์หรือคีย์ลัดบนคีย์บอร์ด…")).font(.callout)
            Spacer()
            Button(tr("Cancel", "ยกเลิก")) { onDone(nil) }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                var f: CGEventFlags = []
                let m = e.modifierFlags
                if m.contains(.control) { f.insert(.maskControl) }
                if m.contains(.option) { f.insert(.maskAlternate) }
                if m.contains(.shift) { f.insert(.maskShift) }
                if m.contains(.command) { f.insert(.maskCommand) }
                let label = KeyNames.special[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "").uppercased()
                onDone(.key(e.keyCode, label, flags: f))
                return nil
            }
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

// MARK: - Sticks tab

struct SticksTab: View {
    @Binding var preset: Preset
    @EnvironmentObject var engine: PadEngine

    var body: some View {
        Form {
            Section(tr("Sticks", "สติ๊ก")) {
                Picker(tr("Left stick", "สติ๊กซ้าย"), selection: $preset.leftStick) {
                    ForEach(StickMode.allCases) { Text($0.title).tag($0) }
                }
                Picker(tr("Right stick", "สติ๊กขวา"), selection: $preset.rightStick) {
                    ForEach(StickMode.allCases) { Text($0.title).tag($0) }
                }
                HStack(spacing: 40) {
                    Spacer()
                    StickPreview(title: tr("Left", "ซ้าย"), value: engine.leftStick, deadzone: preset.deadzone)
                    StickPreview(title: tr("Right", "ขวา"), value: engine.rightStick, deadzone: preset.deadzone)
                    Spacer()
                }
                .padding(.vertical, 6)
                slider(tr("Dead zone", "Dead zone (ระยะที่ไม่ตอบสนอง)"), $preset.deadzone, 0.03...0.35)
            }
            Section(tr("Cursor", "เคอร์เซอร์")) {
                slider(tr("Speed", "ความเร็ว"), $preset.cursorSpeed, 0.2...3)
                slider(tr("Curve (higher = finer control near center)", "ความโค้ง (มาก = ดันเบาๆ ได้ละเอียดขึ้น)"), $preset.acceleration, 1...3.5)
            }
            Section(tr("Scrolling", "การเลื่อน (Scroll)")) {
                slider(tr("Speed", "ความเร็ว"), $preset.scrollSpeed, 0.2...3)
                Toggle(tr("Invert scroll direction", "กลับทิศการเลื่อน"), isOn: $preset.invertScroll)
            }
            Section(tr("Touchpad", "ทัชแพด")) {
                Toggle(tr("Move cursor with touchpad", "ลากนิ้วบนทัชแพดเพื่อขยับเคอร์เซอร์"), isOn: $preset.touchpadCursor)
                slider(tr("Touchpad speed", "ความเร็วทัชแพด"), $preset.touchpadSpeed, 0.2...3).disabled(!preset.touchpadCursor)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: v, in: r).frame(width: 220)
                Text(String(format: "%.2f", v.wrappedValue)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
        }
    }
}

struct StickPreview: View {
    let title: String
    let value: CGPoint
    let deadzone: Double
    private let size: CGFloat = 92

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08))
                Circle().stroke(Color.secondary.opacity(0.35))
                Circle().fill(Color.secondary.opacity(0.18)).frame(width: size * deadzone, height: size * deadzone)
                Path { p in
                    p.move(to: CGPoint(x: size / 2, y: 0)); p.addLine(to: CGPoint(x: size / 2, y: size))
                    p.move(to: CGPoint(x: 0, y: size / 2)); p.addLine(to: CGPoint(x: size, y: size / 2))
                }.stroke(Color.secondary.opacity(0.2))
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    .offset(x: value.x * size / 2, y: -value.y * size / 2)
            }
            .frame(width: size, height: size)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - General

struct GeneralView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: PadEngine
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section(tr("Controller", "จอย")) {
                LabeledContent(tr("Status", "สถานะ")) {
                    Text(engine.controllerName.map { tr("Connected — \($0)", "เชื่อมต่อแล้ว — \($0)") } ?? tr("No controller found", "ยังไม่พบจอย"))
                }
                LabeledContent(tr("Controller type", "ชนิดจอย")) {
                    Text(engine.padKind.title + (engine.controllerName == nil ? tr(" (last connected)", " (ล่าสุดที่ต่อ)") : tr(" — auto-detected", " — ตรวจอัตโนมัติ")))
                }
                if let b = engine.battery {
                    LabeledContent(tr("Battery", "แบตเตอรี่")) {
                        HStack {
                            ProgressView(value: Double(b)).frame(width: 120)
                            Text("\(Int(b * 100))%" + (engine.charging ? tr(" charging", " กำลังชาร์จ") : "")).monospacedDigit()
                        }
                    }
                }
                if engine.controllerName == nil {
                    Text(tr("Connect with a USB cable or pair over Bluetooth\n• DualSense: hold PS + Create until the light blinks\n• Xbox: turn it on, then hold the pair button (top) until the logo blinks fast\nThen choose the controller in System Settings → Bluetooth", "ต่อจอยด้วยสาย USB หรือจับคู่ Bluetooth\n• DualSense: กด PS + Create ค้างจนไฟกะพริบ\n• Xbox: กดปุ่ม Xbox ให้ติด แล้วกดปุ่มจับคู่ (ด้านบน) ค้างจนไฟกะพริบเร็ว\nแล้วเลือกจอยใน System Settings → Bluetooth"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button(tr("Turn off controller now", "ปิดจอยตอนนี้")) { engine.disconnectNow() }.disabled(engine.controllerName == nil)
            }

            Section(tr("Behavior", "การทำงาน")) {
                Picker(tr("Language", "ภาษา"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                Toggle(tr("Enable control", "เปิดใช้งานการควบคุม"), isOn: $engine.enabled)
                Picker(tr("Active preset", "Preset ที่ใช้อยู่"), selection: $store.activeID) {
                    ForEach(store.presets) { Text($0.name).tag($0.id) }
                }
                Picker(tr("Auto turn-off when idle", "ปิดจอยอัตโนมัติเมื่อไม่ได้ใช้"), selection: $store.idleMinutes) {
                    Text(tr("Never", "ไม่ปิด")).tag(0)
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text(tr("\($0) min", "\($0) นาที")).tag($0) }
                }
                Toggle(tr("Open PadFlow at login", "เปิด PadFlow อัตโนมัติเมื่อเข้าเครื่อง"), isOn: Binding(get: { loginOn }, set: setLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section(tr("Permissions", "สิทธิ์")) {
                LabeledContent(tr("Accessibility (mouse/keyboard control)", "Accessibility (ควบคุมเมาส์/คีย์บอร์ด)")) {
                    if axTrusted {
                        Label(tr("Allowed", "อนุญาตแล้ว"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button(tr("Open Settings", "เปิดการตั้งค่า")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                if !axTrusted {
                    Text(tr("If PadFlow is listed but not working, remove it (−) and add it again (+)", "ถ้ามี PadFlow อยู่ในรายการแล้วแต่ยังไม่ทำงาน ให้ลบออก (−) แล้วเพิ่มใหม่ (+)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(tr("Credits", "เครดิต")) {
                Link(tr("3D model “Playstation 5 Dualsense” by AHarmlessPotato (CC BY 4.0)",
                        "โมเดล 3D “Playstation 5 Dualsense” โดย AHarmlessPotato (CC BY 4.0)"),
                     destination: URL(string: "https://sketchfab.com/3d-models/playstation-5-dualsense-878c1f882808477ab81c2fe86d5a3936")!)
                Link(tr("3D model “Xbox Controller” by umkhero (CC BY 4.0)",
                        "โมเดล 3D “Xbox Controller” โดย umkhero (CC BY 4.0)"),
                     destination: URL(string: "https://sketchfab.com/3d-models/xbox-controller-32d17951703b4e05abed11a1c65f5909")!)
                Link(tr("PadFlow source code on GitHub (MIT)", "ซอร์สโค้ด PadFlow บน GitHub (MIT)"),
                     destination: URL(string: "https://github.com/Snow3all/PadFlow")!)
            }
            Section(tr("Tips", "เคล็ดลับ")) {
                Text(tr("• Shift: assign “Shift” to any button, then hold it to use the other buttons’ 2nd-layer actions", "• ปุ่ม Shift: ตั้งปุ่มใดก็ได้เป็น “ปุ่ม Shift” แล้วกดค้างเพื่อใช้คำสั่งชุดที่ 2 ของปุ่มอื่น"))
                Text(tr("• Assign “Next preset” to switch presets from the controller; the light bar color follows", "• ตั้งปุ่มเป็น “สลับไป Preset ถัดไป” เพื่อเปลี่ยน Preset จากจอยได้ทันที สีไฟจอยจะเปลี่ยนตาม"))
                Text(tr("• Right-click a preset on the left to duplicate, export or delete it", "• คลิกขวาที่ Preset ทางซ้ายเพื่อทำสำเนา ส่งออก หรือลบ"))
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle(tr("General", "ทั่วไป"))
        .onReceive(poll) { _ in axTrusted = AXIsProcessTrusted() }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = tr("Couldn't change setting: \(error.localizedDescription)", "ตั้งค่าไม่สำเร็จ: \(error.localizedDescription)")
        }
        loginOn = SMAppService.mainApp.status == .enabled
    }
}
