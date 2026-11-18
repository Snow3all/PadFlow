// Controller3D.swift — โมเดลจอย 3 มิติ (SceneKit) ที่คลิกเลือกปุ่ม หมุนได้ และขยับตามจอยจริง
import SwiftUI
import SceneKit
import CoreImage

struct Controller3DView: NSViewRepresentable {
    let kind: PadKind
    let preset: Preset
    @Binding var selected: PadButton
    @Binding var hovered: PadButton?
    let pressed: Set<PadButton>
    let left: CGPoint, right: CGPoint

    func makeCoordinator() -> PadScene { PadScene(kind: kind) }

    func makeNSView(context: Context) -> PadSCNView {
        let c = context.coordinator
        let v = PadSCNView(frame: .zero)
        v.scene = c.scene
        v.pointOfView = c.cameraNode
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.onDrag = { dx, dy in c.rotate(dx: dx, dy: dy) }
        v.onReset = { c.resetRotation() }
        v.fitHalfW = c.fitHalfW
        v.fitHalfH = c.fitHalfH
        v.onClick = { [weak v] p in
            guard let v, let b = c.button(at: p, in: v) else { return }
            c.onSelect?(b)
        }
        v.onHover = { [weak v] p in
            guard let v else { return }
            let b = p.flatMap { c.button(at: $0, in: v) }
            c.onHover?(b)
            (b == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
        }
        c.intro()
        return v
    }

    func updateNSView(_ v: PadSCNView, context: Context) {
        let c = context.coordinator
        c.onSelect = { selected = $0 }
        c.onHover = { b in if hovered != b { hovered = b } }
        c.update(preset: preset, selected: selected, hovered: hovered, pressed: pressed, left: left, right: right)
    }
}

// MARK: - View ที่รับเมาส์

final class PadSCNView: SCNView {
    var onClick: ((CGPoint) -> Void)?
    var onHover: ((CGPoint?) -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onReset: (() -> Void)?
    var fitHalfW: CGFloat = 4.0, fitHalfH: CGFloat = 3.25
    private var downPoint: CGPoint?
    private var dragging = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    /// ปรับกล้องให้เห็นจอยเต็มตัวไม่ว่าพื้นที่จะกว้างหรือสูง
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let cam = pointOfView?.camera, newSize.width > 0, newSize.height > 0 else { return }
        let dist: CGFloat = 10.4, halfW = fitHalfW, halfH = fitHalfH
        if newSize.width / newSize.height < halfW / halfH {
            cam.projectionDirection = .horizontal
            cam.fieldOfView = 2 * atan(halfW / dist) * 180 / .pi
        } else {
            cam.projectionDirection = .vertical
            cam.fieldOfView = 2 * atan(halfH / dist) * 180 / .pi
        }
    }

    private func local(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseDown(with e: NSEvent) {
        downPoint = local(e)
        dragging = false
        if e.clickCount == 2 { onReset?() }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let d = downPoint else { return }
        let p = local(e)
        if dragging || hypot(p.x - d.x, p.y - d.y) > 4 {
            dragging = true
            NSCursor.closedHand.set()
            onDrag?(e.deltaX, e.deltaY)
        }
    }

    override func mouseUp(with e: NSEvent) {
        if !dragging, let d = downPoint { onClick?(d) }
        downPoint = nil
        dragging = false
    }

    override func mouseMoved(with e: NSEvent) { onHover?(local(e)) }
    override func mouseExited(with e: NSEvent) { onHover?(nil) }
}

// MARK: - Scene

final class PadScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let pivot = SCNNode()
    private var parts: [PadButton: Part] = [:]
    private var stickPivots: [PadButton: SCNNode] = [:]
    private var lightBar: [SCNMaterial] = []
    private var yaw: CGFloat = 0, pitch: CGFloat = 0
    private var lastLight: NSColor?

    var onSelect: ((PadButton) -> Void)?
    var onHover: ((PadButton?) -> Void)?

    private struct Part {
        let node: SCNNode
        let base: SCNVector3
        let press: SCNVector3
        let materials: [SCNMaterial]
        let color: NSColor
        var textured = false
        var lightEmission = false   // ใช้แผนที่เรืองแสงของแถบไฟเป็นค่าปกติ
    }

    private(set) var fitHalfW: CGFloat = 4.0, fitHalfH: CGFloat = 3.25
    private var usingModel = false
    private var lightMaterials: [SCNMaterial] = []   // วัสดุที่มีแผนที่เรืองแสงของแถบไฟ
    private var emissiveSource: CIImage?
    private var lightImage: CGImage?

    // สีและความสูงของแต่ละชั้น (แกน z = ด้านหน้าจอย)
    private let white = NSColor(white: 0.93, alpha: 1)
    private let black = NSColor(white: 0.045, alpha: 1)
    private let keyColor = NSColor(white: 0.09, alpha: 1)          // ไก, สติ๊ก
    private let faceColor = NSColor(white: 0.9, alpha: 1)          // ปุ่มหน้า / D-pad (ขาวใส)
    private let coreFront: CGFloat = 0.35     // ผิวแผงดำ
    private let wingFront: CGFloat = 0.43     // ผิวปีกสีขาว

    let kind: PadKind

    init(kind: PadKind) {
        self.kind = kind
        scene.rootNode.addChildNode(pivot)
        scene.lightingEnvironment.contents = Self.environmentImage()
        scene.lightingEnvironment.intensity = 1.35
        buildLights()
        buildCamera()
        if loadModel() {
            usingModel = true
            fitHalfW = 3.95; fitHalfH = 3.0
            cameraNode.position = SCNVector3(0, 2.6, 9.6)
            cameraNode.look(at: SCNVector3(0, -0.05, 0))
        } else {
            buildShell()
            buildTouchpad()
            buildFaceButtons()
            buildDpad()
            buildSticks()
            buildCenterButtons()
            buildShoulders()
        }
    }

    // MARK: Real model (PadModel.scn / XboxModel.scn + Textures ใน Resources)

    private func loadModel() -> Bool {
        guard let url = Bundle.main.url(forResource: kind == .xbox ? "XboxModel" : "PadModel", withExtension: "scn"),
              let src = try? SCNScene(url: url, options: nil),
              let model = src.rootNode.childNode(withName: "PadModel", recursively: false),
              let texDir = Bundle.main.resourceURL?.appendingPathComponent("Textures")
        else { return false }

        func tex(_ n: String) -> URL? {
            let u = texDir.appendingPathComponent(n)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        emissiveSource = tex("1011_emissive.jpg").flatMap { CIImage(contentsOf: $0) }

        var shared: [String: SCNMaterial] = [:]
        func material(_ id: String) -> SCNMaterial {
            if let m = shared[id] { return m }
            let m = SCNMaterial()
            m.name = id
            m.lightingModel = .physicallyBased
            if id == "xbox" {
                m.diffuse.contents = tex("xbox_albedo.png")
                m.roughness.contents = 0.42
                m.metalness.contents = 0.0
                m.isDoubleSided = true
                m.emission.contents = NSColor.black
                shared[id] = m
                return m
            }
            m.diffuse.contents = tex("\(id)_albedo.jpg")
            m.normal.contents = tex("\(id)_normal.jpg")
            m.roughness.contents = tex("\(id)_roughness.jpg")
            m.metalness.contents = tex("\(id)_metallic.jpg")
            if id != "1001", let t = tex("\(id)_transp.jpg") { m.transparent.contents = t; m.transparencyMode = .rgbZero }
            m.emission.contents = NSColor.black
            if id == "1011" { lightMaterials.append(m) }
            shared[id] = m
            return m
        }

        model.removeFromParentNode()
        model.scale = SCNVector3(3.3, 3.3, 3.3)
        pivot.addChildNode(model)

        for grp in model.childNodes {
            let name = grp.name ?? ""
            let button = PadButton(rawValue: name)
            var mats: [SCNMaterial] = []
            var usesLight = false
            for part in grp.childNodes {
                guard let g = part.geometry else { continue }
                part.castsShadow = true
                let id = g.materials.first?.name ?? "1002"
                if name == "lightbar" {
                    let m = glow(.systemBlue)
                    g.materials = [m]
                    lightBar.append(m)
                } else if button != nil {
                    let m = material(id).copy() as! SCNMaterial
                    g.materials = [m]
                    mats.append(m)
                    if id == "1011" { lightMaterials.append(m); usesLight = true }
                } else {
                    g.materials = [material(id)]
                }
            }
            guard let b = button else { continue }
            let press: SCNVector3
            switch b {
            case .l1, .r1: press = SCNVector3(0, -0.012, 0)
            case .l2, .r2: press = SCNVector3(0, -0.02, -0.015)
            case .touchpad: press = SCNVector3(0, 0, -0.006)
            case .create, .options: press = SCNVector3(0, 0, -0.008)
            case .l3, .r3: press = SCNVector3(0, 0, -0.015)
            default: press = SCNVector3(0, 0, -0.012)
            }
            register(b, grp, press: press, materials: mats, color: .white)
            parts[b]?.textured = true
            parts[b]?.lightEmission = usesLight
            if b == .l3 || b == .r3 { stickPivots[b] = grp }
            // สัญลักษณ์บนปุ่มหน้า (ในโมเดลพิมพ์ไว้ด้วยความโปร่งใส ซึ่งเราไม่ได้ใช้)
            let faceCenters: [PadButton: CGPoint] = [.triangle: CGPoint(x: 0.623, y: 0.423), .cross: CGPoint(x: 0.623, y: 0.129),
                                                     .square: CGPoint(x: 0.476, y: 0.276), .circle: CGPoint(x: 0.770, y: 0.276)]
            if kind == .dualSense, let c = faceCenters[b] {
                let (_, mx) = grp.boundingBox
                let sym = symbol(b, NSColor(white: 0.5, alpha: 1))
                sym.scale = SCNVector3(0.3, 0.3, 0.3)
                sym.position = SCNVector3(c.x, c.y, mx.z + 0.001)
                grp.addChildNode(sym)
            }
        }
        return true
    }

    /// แผนที่เรืองแสงของแถบไฟ ย้อมเป็นสีของ Preset
    private func tintedLight(_ c: NSColor) -> CGImage? {
        guard let src = emissiveSource else { return nil }
        let k: CGFloat = 1.6
        let f = CIFilter(name: "CIColorMatrix")!
        f.setValue(src, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: c.redComponent * k / 3, y: c.redComponent * k / 3, z: c.redComponent * k / 3, w: 0), forKey: "inputRVector")
        f.setValue(CIVector(x: c.greenComponent * k / 3, y: c.greenComponent * k / 3, z: c.greenComponent * k / 3, w: 0), forKey: "inputGVector")
        f.setValue(CIVector(x: c.blueComponent * k / 3, y: c.blueComponent * k / 3, z: c.blueComponent * k / 3, w: 0), forKey: "inputBVector")
        f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        guard let out = f.outputImage else { return nil }
        return CIContext().createCGImage(out, from: src.extent)
    }

    // MARK: Interaction

    func button(at p: CGPoint, in v: SCNView) -> PadButton? {
        for hit in v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var n: SCNNode? = hit.node
            while let cur = n {
                if let name = cur.name, let b = PadButton(rawValue: name) { return b }
                n = cur.parent
            }
        }
        return nil
    }

    func rotate(dx: CGFloat, dy: CGFloat) {
        yaw = min(max(yaw + dx * 0.008, -0.9), 0.9)
        pitch = min(max(pitch + dy * 0.008, -0.7), 0.6)
        pivot.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    func resetRotation() {
        yaw = 0; pitch = 0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pivot.eulerAngles = SCNVector3(0, 0, 0)
        SCNTransaction.commit()
    }

    func intro() {
        pivot.eulerAngles = SCNVector3(0.35, -0.7, 0)
        pivot.opacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in self.playIntro() }
    }

    private func playIntro() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.9
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        pivot.eulerAngles = SCNVector3(0, 0, 0)
        pivot.opacity = 1
        SCNTransaction.commit()
    }

    func update(preset: Preset, selected: PadButton, hovered: PadButton?, pressed: Set<PadButton>, left: CGPoint, right: CGPoint) {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        // สีแถบไฟ: ตั้งตรงๆ ไม่ทำแอนิเมชัน (ไม่งั้นอาจค้างเป็นสีดำ)
        let lc = NSColor(srgbRed: preset.light.r, green: preset.light.g, blue: preset.light.b, alpha: 1)
        if lc != lastLight {
            lastLight = lc
            if usingModel { lightImage = tintedLight(lc) }
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            for m in lightBar { m.diffuse.contents = lc; m.emission.contents = lc }
            for m in lightMaterials { m.emission.contents = (lightImage as Any?) ?? NSColor.black }
            SCNTransaction.commit()
        }

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.07
        for (b, part) in parts {
            let isDown = pressed.contains(b)
            let color: NSColor
            if isDown { color = accent }
            else if b == selected { color = part.color.blended(withFraction: 0.6, of: accent) ?? accent }
            else if b == hovered { color = part.color.blended(withFraction: 0.25, of: accent) ?? part.color }
            else { color = part.color }
            if part.textured {
                let amount: CGFloat = isDown ? 0.75 : (b == selected ? 0.5 : (b == hovered ? 0.22 : 0))
                let glowValue: Any = amount > 0
                    ? (accent.blended(withFraction: 1 - amount, of: .black) ?? accent)
                    : (part.lightEmission ? ((lightImage as Any?) ?? NSColor.black) : NSColor.black)
                for m in part.materials { m.emission.contents = glowValue }
            } else {
                let glow = b == selected || isDown ? (accent.blended(withFraction: 0.55, of: .black) ?? .black) : NSColor.black
                for m in part.materials { m.diffuse.contents = color; m.emission.contents = glow }
            }
            part.node.position = isDown
                ? SCNVector3(part.base.x + part.press.x, part.base.y + part.press.y, part.base.z + part.press.z)
                : part.base
        }
        let tilt: CGFloat = usingModel ? 0.3 : 0.38
        stickPivots[.l3]?.eulerAngles = SCNVector3(-left.y * tilt, left.x * tilt, 0)
        stickPivots[.r3]?.eulerAngles = SCNVector3(-right.y * tilt, right.x * tilt, 0)
        SCNTransaction.commit()
    }

    // MARK: Materials & geometry helpers

    private func plastic(_ c: NSColor, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = 0.0
        return m
    }

    private func glow(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.emission.contents = c
        return m
    }

    /// ภาพสภาพแวดล้อมสำหรับเงาสะท้อนบนพลาสติก (สตูดิโอถ่ายภาพจำลอง)
    private static func environmentImage() -> NSImage {
        let w: CGFloat = 1024, h: CGFloat = 512
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSGradient(colors: [NSColor(white: 0.18, alpha: 1), NSColor(white: 0.45, alpha: 1), NSColor(white: 0.85, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 380, y: 360, width: 260, height: 90), xRadius: 40, yRadius: 40).fill()
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 280, width: 140, height: 120), xRadius: 30, yRadius: 30).fill()
        NSBezierPath(roundedRect: NSRect(x: 820, y: 280, width: 140, height: 120), xRadius: 30, yRadius: 30).fill()
        img.unlockFocus()
        return img
    }

    private static let roundProfile: NSBezierPath = {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: 0, y: 1))
        p.appendArc(withCenter: CGPoint(x: 0, y: 0), radius: 1, startAngle: 90, endAngle: 0, clockwise: true)
        p.flatness = 0.02
        return p
    }()

    private func extrude(_ path: NSBezierPath, depth: CGFloat, chamfer: CGFloat, _ m: SCNMaterial) -> SCNNode {
        path.flatness = 0.012
        let s = SCNShape(path: path, extrusionDepth: depth)
        s.chamferRadius = chamfer
        s.chamferProfile = Self.roundProfile
        s.materials = [m]
        return SCNNode(geometry: s)
    }

    private func circle(_ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
    }

    private func pill(_ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
    }

    /// รูปหลายเหลี่ยมที่มุมโค้ง
    private func roundedPoly(_ pts: [CGPoint], _ radii: [CGFloat]) -> NSBezierPath {
        let p = NSBezierPath()
        let n = pts.count
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for i in 0..<n { p.appendArc(from: pts[i], to: pts[(i + 1) % n], radius: radii[i]) }
        p.close()
        return p
    }

    /// แถบเส้นตามแนวจุดที่กำหนด
    private func strip(_ pts: [CGPoint], width: CGFloat) -> NSBezierPath {
        var a: [CGPoint] = [], b: [CGPoint] = []
        for i in pts.indices {
            let p0 = pts[max(i - 1, 0)], p1 = pts[min(i + 1, pts.count - 1)]
            let dx = p1.x - p0.x, dy = p1.y - p0.y, l = max(hypot(dx, dy), 0.0001)
            let nx = -dy / l * width / 2, ny = dx / l * width / 2
            a.append(CGPoint(x: pts[i].x + nx, y: pts[i].y + ny))
            b.append(CGPoint(x: pts[i].x - nx, y: pts[i].y - ny))
        }
        let p = NSBezierPath()
        p.move(to: a[0]); a.dropFirst().forEach { p.line(to: $0) }
        b.reversed().forEach { p.line(to: $0) }
        p.close()
        return p
    }

    private func bezierPoints(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, n: Int) -> [CGPoint] {
        (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n), u = 1 - t
            let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x
            let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y
            return CGPoint(x: x, y: y)
        }
    }

    private func register(_ b: PadButton, _ node: SCNNode, press: SCNVector3, materials: [SCNMaterial], color: NSColor) {
        node.name = b.rawValue
        parts[b] = Part(node: node, base: node.position, press: press, materials: materials, color: color)
    }

    @discardableResult
    private func label(_ s: String, at p: SCNVector3, size: CGFloat, parent: SCNNode) -> SCNNode {
        let t = SCNText(string: s, extrusionDepth: 0)
        t.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        t.flatness = 0.05
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = NSColor(white: 0.62, alpha: 1)
        t.materials = [m]
        let n = SCNNode(geometry: t)
        let (mn, mx) = n.boundingBox
        n.pivot = SCNMatrix4MakeTranslation((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0)
        let k = size / 10
        n.scale = SCNVector3(k, k, k)
        n.position = p
        parent.addChildNode(n)
        return n
    }

    // MARK: Outline (มองจากด้านหน้า, ครึ่งขวา จากกลางบนลงไปกลางล่าง)

    private typealias Seg = (p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint)

    private static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private let topInner: Seg   = (P(0, 1.33), P(0.6, 1.33), P(1.1, 1.33), P(1.47, 1.33))
    private let topOuter: Seg   = (P(1.47, 1.33), P(1.95, 1.34), P(2.45, 1.38), P(2.78, 1.15))
    private let shoulder: Seg   = (P(2.78, 1.15), P(3.12, 0.92), P(3.3, 0.55), P(3.3, 0.05))
    private let outerGrip: Seg  = (P(3.3, 0.05), P(3.3, -1.0), P(3.27, -2.1), P(2.95, -2.75))
    private let gripTip: Seg    = (P(2.95, -2.75), P(2.65, -3.35), P(1.75, -3.4), P(1.45, -2.85))
    private let innerGripA: Seg = (P(1.45, -2.85), P(1.32, -2.6), P(1.29, -2.32), P(1.3, -2.1))
    private let innerGripB: Seg = (P(1.3, -2.1), P(1.3, -1.96), P(1.16, -1.88), P(1.0, -1.88))
    private let bottom: Seg     = (P(1.0, -1.88), P(0.66, -1.88), P(0.33, -1.88), P(0, -1.88))

    private func mirror(_ s: Seg) -> Seg {
        let m = { (p: CGPoint) in CGPoint(x: -p.x, y: p.y) }
        return (m(s.p3), m(s.c2), m(s.c1), m(s.p0))   // กลับทิศ + สะท้อน
    }

    private func path(_ segs: [Seg], closeWith extra: ((NSBezierPath) -> Void)? = nil) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: segs[0].p0)
        for s in segs { p.curve(to: s.p3, controlPoint1: s.c1, controlPoint2: s.c2) }
        extra?(p)
        p.close()
        return p
    }

    // MARK: Build

    private func buildLights() {
        let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional
        key.light!.intensity = 700
        key.light!.castsShadow = true
        key.light!.shadowMode = .deferred
        key.light!.shadowRadius = 10
        key.light!.shadowSampleCount = 16
        key.light!.shadowColor = NSColor(white: 0, alpha: 0.4)
        key.position = SCNVector3(-3, -2, 9)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)

        let rim = SCNNode(); rim.light = SCNLight(); rim.light!.type = .directional
        rim.light!.intensity = 350
        rim.position = SCNVector3(2, 6, -3)
        rim.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(rim)

        // พื้นหลังรับเงา ทำให้จอยดูลอยอยู่เหนือพื้น
        let floor = SCNPlane(width: 40, height: 40)
        let fm = SCNMaterial(); fm.lightingModel = .shadowOnly; fm.writesToDepthBuffer = false
        floor.materials = [fm]
        let fn = SCNNode(geometry: floor)
        fn.position = SCNVector3(0, 0, -1.7)
        fn.renderingOrder = -10
        scene.rootNode.addChildNode(fn)
    }

    private func buildCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 27
        cam.zNear = 0.1
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, -4.0, 9.6)
        cameraNode.look(at: SCNVector3(0, -0.5, 0))
        scene.rootNode.addChildNode(cameraNode)
    }

    private func buildShell() {
        let right = [topInner, topOuter, shoulder, outerGrip, gripTip, innerGripA, innerGripB, bottom]
        let left = right.reversed().map(mirror)

        // แกนสีดำ (ทั้งตัว)
        let core = extrude(path(right + left), depth: 0.7, chamfer: 0.32, plastic(black, rough: 0.55))
        core.castsShadow = true
        pivot.addChildNode(core)

        // ปีกสีขาวสองข้าง (ขอบในเลียบทัชแพด แล้ววนรอบสติ๊กลงไปที่ด้ามจับ)
        let rightWing = NSBezierPath()
        rightWing.move(to: topOuter.p0)
        for g in [topOuter, shoulder, outerGrip, gripTip, innerGripA] {
            rightWing.curve(to: g.p3, controlPoint1: g.c1, controlPoint2: g.c2)
        }
        rightWing.curve(to: CGPoint(x: 1.76, y: -1.0), controlPoint1: CGPoint(x: 1.45, y: -1.7), controlPoint2: CGPoint(x: 1.73, y: -1.35))
        rightWing.curve(to: CGPoint(x: 1.2, y: -0.13), controlPoint1: CGPoint(x: 1.77, y: -0.55), controlPoint2: CGPoint(x: 1.44, y: -0.18))
        rightWing.close()
        let leftWing = rightWing.copy() as! NSBezierPath
        leftWing.transform(using: AffineTransform(scaleByX: -1, byY: 1))
        for p in [rightWing, leftWing] {
            let wing = extrude(p, depth: 0.28, chamfer: 0.13, plastic(white, rough: 0.5))
            wing.position.z = wingFront - 0.14
            wing.castsShadow = true
            pivot.addChildNode(wing)
        }
    }

    private func buildTouchpad() {
        let tpColor = NSColor(white: 0.95, alpha: 1)
        let m = plastic(tpColor, rough: 0.38)
        let shape = roundedPoly([CGPoint(x: -1.1, y: -0.07), CGPoint(x: 1.1, y: -0.07), CGPoint(x: 1.43, y: 1.32), CGPoint(x: -1.43, y: 1.32)],
                                [0.26, 0.26, 0.06, 0.06])
        let tp = extrude(shape, depth: 0.1, chamfer: 0.04, m)
        tp.position.z = coreFront + 0.05
        pivot.addChildNode(tp)
        register(.touchpad, tp, press: SCNVector3(0, 0, -0.03), materials: [m], color: tpColor)

        // แถบไฟโค้งตามขอบทัชแพด
        for s in [CGFloat(1), -1] {
            let pts = bezierPoints(CGPoint(x: 1.455 * s, y: 1.22), CGPoint(x: 1.38 * s, y: 0.85),
                                   CGPoint(x: 1.25 * s, y: 0.25), CGPoint(x: 1.12 * s, y: -0.1), n: 32)
            let m = glow(NSColor(srgbRed: 0.1, green: 0.4, blue: 1, alpha: 1))
            let bar = extrude(strip(pts, width: 0.05), depth: 0.03, chamfer: 0.01, m)
            bar.position.z = coreFront + 0.02
            pivot.addChildNode(bar)
            lightBar.append(m)
        }
    }

    private func buildFaceButtons() {
        let center = CGPoint(x: 2.13, y: 0.11), d: CGFloat = 0.5
        let symColor = NSColor(white: 0.42, alpha: 1)
        let defs: [(PadButton, CGPoint)] = [
            (.triangle, CGPoint(x: 0, y: d)), (.cross, CGPoint(x: 0, y: -d)),
            (.square, CGPoint(x: -d, y: 0)), (.circle, CGPoint(x: d, y: 0)),
        ]
        for (b, off) in defs {
            let holder = SCNNode()
            holder.position = SCNVector3(center.x + off.x, center.y + off.y, wingFront + 0.02)
            let m = plastic(faceColor, rough: 0.14)
            let cap = extrude(circle(0.2), depth: 0.14, chamfer: 0.05, m)
            holder.addChildNode(cap)
            let ringGeo = SCNTorus(ringRadius: 0.2, pipeRadius: 0.014)
            ringGeo.ringSegmentCount = 64
            ringGeo.materials = [plastic(NSColor(white: 0.55, alpha: 1), rough: 0.4)]
            let ring = SCNNode(geometry: ringGeo); ring.eulerAngles.x = .pi / 2; ring.position.z = -0.03
            holder.addChildNode(ring)
            let sym = symbol(b, symColor)
            sym.position.z = 0.072
            holder.addChildNode(sym)
            pivot.addChildNode(holder)
            register(b, holder, press: SCNVector3(0, 0, -0.05), materials: [m], color: faceColor)
        }
    }

    private func symbol(_ b: PadButton, _ c: NSColor) -> SCNNode {
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c
        let n = SCNNode()
        switch b {
        case .cross:
            for a in [CGFloat.pi / 4, -CGFloat.pi / 4] {
                let bar = SCNNode(geometry: SCNBox(width: 0.2, height: 0.026, length: 0.006, chamferRadius: 0.01))
                bar.geometry?.materials = [m]
                bar.eulerAngles.z = a
                n.addChildNode(bar)
            }
        case .circle:
            let t = SCNTorus(ringRadius: 0.075, pipeRadius: 0.013)
            t.ringSegmentCount = 48
            t.materials = [m]
            let tn = SCNNode(geometry: t); tn.eulerAngles.x = .pi / 2; tn.scale.y = 0.3
            n.addChildNode(tn)
        case .square, .triangle:
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            func poly(_ pts: [CGPoint]) { path.move(to: pts[0]); pts.dropFirst().forEach { path.line(to: $0) }; path.close() }
            if b == .square {
                poly([CGPoint(x: -0.075, y: -0.075), CGPoint(x: 0.075, y: -0.075), CGPoint(x: 0.075, y: 0.075), CGPoint(x: -0.075, y: 0.075)])
                poly([CGPoint(x: -0.05, y: -0.05), CGPoint(x: 0.05, y: -0.05), CGPoint(x: 0.05, y: 0.05), CGPoint(x: -0.05, y: 0.05)])
            } else {
                poly([CGPoint(x: 0, y: 0.09), CGPoint(x: 0.085, y: -0.06), CGPoint(x: -0.085, y: -0.06)])
                poly([CGPoint(x: 0, y: 0.05), CGPoint(x: 0.051, y: -0.04), CGPoint(x: -0.051, y: -0.04)])
            }
            let s = SCNShape(path: path, extrusionDepth: 0.004)
            s.materials = [m]
            n.addChildNode(SCNNode(geometry: s))
        default: break
        }
        return n
    }

    private func buildDpad() {
        let c = CGPoint(x: -2.23, y: 0.11)
        let defs: [(PadButton, CGFloat)] = [(.up, 0), (.right, -.pi / 2), (.down, .pi), (.left, .pi / 2)]
        for (b, angle) in defs {
            let arm = roundedPoly([CGPoint(x: 0, y: 0.07), CGPoint(x: 0.125, y: 0.18), CGPoint(x: 0.125, y: 0.43),
                                   CGPoint(x: -0.125, y: 0.43), CGPoint(x: -0.125, y: 0.18)],
                                  [0.025, 0.025, 0.05, 0.05, 0.025])
            let m = plastic(faceColor, rough: 0.16)
            let node = extrude(arm, depth: 0.11, chamfer: 0.035, m)
            let am = SCNMaterial(); am.lightingModel = .constant; am.diffuse.contents = NSColor(white: 0.45, alpha: 1)
            let tri = NSBezierPath()
            tri.move(to: CGPoint(x: 0, y: 0.35)); tri.line(to: CGPoint(x: 0.045, y: 0.28)); tri.line(to: CGPoint(x: -0.045, y: 0.28)); tri.close()
            let arrow = SCNNode(geometry: { let s = SCNShape(path: tri, extrusionDepth: 0.004); s.materials = [am]; return s }())
            arrow.position.z = 0.057
            let holder = SCNNode()
            holder.position = SCNVector3(c.x, c.y, wingFront + 0.035)
            holder.eulerAngles.z = angle
            holder.addChildNode(node)
            holder.addChildNode(arrow)
            pivot.addChildNode(holder)
            register(b, holder, press: SCNVector3(0, 0, -0.045), materials: [m], color: faceColor)
        }
    }

    private func buildSticks() {
        for (b, x) in [(PadButton.l3, CGFloat(-1.01)), (.r3, 1.01)] {
            let base = SCNVector3(x, -0.67, coreFront)
            let well = extrude(circle(0.43), depth: 0.03, chamfer: 0.012, plastic(NSColor(white: 0.02, alpha: 1), rough: 0.3))
            well.position = SCNVector3(base.x, base.y, coreFront + 0.0)
            pivot.addChildNode(well)

            let holder = SCNNode(); holder.position = base
            let tiltNode = SCNNode()
            holder.addChildNode(tiltNode)

            let dome = SCNSphere(radius: 0.28)
            dome.segmentCount = 48
            dome.materials = [plastic(NSColor(white: 0.03, alpha: 1), rough: 0.35)]
            let domeN = SCNNode(geometry: dome); domeN.scale = SCNVector3(1, 1, 0.35)
            tiltNode.addChildNode(domeN)

            let shaft = extrude(circle(0.12), depth: 0.3, chamfer: 0.02, plastic(black, rough: 0.5))
            shaft.position.z = 0.18
            tiltNode.addChildNode(shaft)

            let capColor = NSColor(white: 0.07, alpha: 1)
            let capM = plastic(capColor, rough: 0.8)
            let cap = extrude(circle(0.33), depth: 0.13, chamfer: 0.055, capM)
            cap.position.z = 0.38
            tiltNode.addChildNode(cap)
            // ยอดเว้า
            let dish = SCNSphere(radius: 0.245)
            dish.segmentCount = 48
            let dishM = plastic(NSColor(white: 0.11, alpha: 1), rough: 0.9)
            dish.materials = [dishM]
            let dishN = SCNNode(geometry: dish); dishN.scale = SCNVector3(1, 1, 0.12)
            dishN.position.z = 0.43
            tiltNode.addChildNode(dishN)
            // ลายกันลื่นรอบขอบ
            for i in 0..<36 {
                let a = CGFloat(i) / 36 * .pi * 2
                let rib = SCNNode(geometry: SCNBox(width: 0.03, height: 0.012, length: 0.1, chamferRadius: 0.005))
                rib.geometry?.materials = [capM]
                rib.position = SCNVector3(cos(a) * 0.33, sin(a) * 0.33, 0.38)
                rib.eulerAngles.z = a
                tiltNode.addChildNode(rib)
            }
            pivot.addChildNode(holder)
            stickPivots[b] = tiltNode
            register(b, holder, press: SCNVector3(0, 0, -0.06), materials: [capM, dishM], color: capColor)
        }
    }

    private func buildCenterButtons() {
        // Create / Options — บนปีกขาว ข้างมุมบนของทัชแพด
        for (b, s) in [(PadButton.create, CGFloat(-1)), (.options, 1)] {
            let cColor = NSColor(white: 0.86, alpha: 1)
            let m = plastic(cColor, rough: 0.2)
            let node = extrude(pill(0.1, 0.3), depth: 0.08, chamfer: 0.03, m)
            node.position = SCNVector3(1.64 * s, 0.93, wingFront + 0.03)
            node.eulerAngles.z = -0.22 * s
            pivot.addChildNode(node)
            register(b, node, press: SCNVector3(0, 0, -0.035), materials: [m], color: cColor)
        }

        // ปุ่ม PS (ไม่มีโลโก้) และปุ่มปิดไมค์ — macOS ใช้อยู่ ตั้งค่าไม่ได้
        let ps = extrude(circle(0.13), depth: 0.07, chamfer: 0.03, plastic(NSColor(white: 0.08, alpha: 1), rough: 0.12))
        ps.position = SCNVector3(0, -0.85, coreFront + 0.03)
        pivot.addChildNode(ps)
        let mute = extrude(pill(0.3, 0.075), depth: 0.05, chamfer: 0.02, plastic(NSColor(white: 0.12, alpha: 1), rough: 0.3))
        mute.position = SCNVector3(0, -1.17, coreFront + 0.02)
        pivot.addChildNode(mute)

        // ไมค์ใต้ปุ่มปิดไมค์
        let mic = SCNNode(geometry: SCNCylinder(radius: 0.018, height: 0.01))
        mic.geometry?.materials = [plastic(.black, rough: 1)]
        mic.eulerAngles.x = .pi / 2
        mic.position = SCNVector3(0, -1.32, coreFront + 0.002)
        pivot.addChildNode(mic)

        // รูลำโพงใต้ทัชแพด เหนือปุ่ม PS
        let holeM = plastic(NSColor(white: 0.0, alpha: 1), rough: 1)
        for row in 0..<3 {
            for col in -3...3 {
                let h = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.01))
                h.geometry?.materials = [holeM]
                h.eulerAngles.x = .pi / 2
                h.position = SCNVector3(CGFloat(col) * 0.05 + (row % 2 == 0 ? 0 : 0.025), -0.24 - CGFloat(row) * 0.045, coreFront + 0.002)
                pivot.addChildNode(h)
            }
        }
    }

    private func buildShoulders() {
        for (side, sx) in [("L", CGFloat(-1)), ("R", 1)] {
            let x = 2.12 * sx
            let bm = plastic(keyColor, rough: 0.3)
            let bumper = extrude(roundedPoly([CGPoint(x: -0.56, y: -0.16), CGPoint(x: 0.56, y: -0.16),
                                              CGPoint(x: 0.5, y: 0.16), CGPoint(x: -0.5, y: 0.16)],
                                             [0.1, 0.1, 0.13, 0.13]),
                                 depth: 0.4, chamfer: 0.1, bm)
            bumper.position = SCNVector3(x, 1.52, 0.18)
            bumper.eulerAngles.z = -0.07 * sx
            pivot.addChildNode(bumper)
            label("\(side)1", at: SCNVector3(0, 0.01, 0.205), size: 0.15, parent: bumper)
            register(side == "L" ? .l1 : .r1, bumper, press: SCNVector3(0, -0.05, 0), materials: [bm], color: keyColor)

            let tm = plastic(keyColor, rough: 0.28)
            let trig = extrude(roundedPoly([CGPoint(x: -0.44, y: -0.28), CGPoint(x: 0.44, y: -0.28),
                                            CGPoint(x: 0.4, y: 0.3), CGPoint(x: -0.4, y: 0.3)],
                                           [0.12, 0.12, 0.2, 0.2]),
                               depth: 0.32, chamfer: 0.14, tm)
            trig.position = SCNVector3(x, 2.12, -0.2)
            trig.eulerAngles = SCNVector3(0.3, 0, -0.06 * sx)
            pivot.addChildNode(trig)
            label("\(side)2", at: SCNVector3(0, 0.04, 0.165), size: 0.15, parent: trig)
            register(side == "L" ? .l2 : .r2, trig, press: SCNVector3(0, -0.1, -0.03), materials: [tm], color: keyColor)
        }
    }
}
