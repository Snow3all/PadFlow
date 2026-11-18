// Usage: swiftc -O bake_dualsense.swift -o bake -framework SceneKit && ./bake model.dae ../../Resources/PadModel.scn
// (the .dae must live outside /tmp — SceneKit loads Collada through an XPC service)
// แยกโมเดล DualSense เป็นชิ้นตามปุ่ม แล้วบันทึกเป็น .scn
import SceneKit
let args = CommandLine.arguments
let scene = try! SCNScene(url: URL(fileURLWithPath: args[1]), options: [.convertToYUp: true])
let outURL = URL(fileURLWithPath: args[2])

struct Comp { var tris: [UInt32] = []; var mn = SIMD3<Float>(repeating: 1e9); var mx = SIMD3<Float>(repeating: -1e9)
    var center: SIMD3<Float> { (mn + mx) / 2 }; var size: SIMD3<Float> { mx - mn } }

func floats(_ s: SCNGeometrySource) -> [[Float]] {
    var out = [[Float]](repeating: [], count: s.vectorCount)
    s.data.withUnsafeBytes { raw in
        for i in 0..<s.vectorCount {
            let o = s.dataOffset + i * s.dataStride
            out[i] = (0..<s.componentsPerVector).map { raw.load(fromByteOffset: o + $0 * s.bytesPerComponent, as: Float.self) }
        }
    }
    return out
}

func classify(_ mat: String, _ c: Comp) -> String {
    let p = c.center, s = c.size
    if mat == "1001" {
        if abs(p.x + 0.624) < 0.16 && p.y > 0.1 && p.y < 0.46 && p.z > 0.25 {
            let dx = p.x + 0.624, dy = p.y - 0.277
            return abs(dx) > abs(dy) ? (dx < 0 ? "left" : "right") : (dy > 0 ? "up" : "down")
        }
        if p.x > 0.4 && p.y > 0.06 && p.y < 0.5 && p.z > 0.25 && s.x < 0.2 {
            let dx = p.x - 0.623, dy = p.y - 0.276
            return abs(dx) > abs(dy) ? (dx < 0 ? "square" : "circle") : (dy > 0 ? "triangle" : "cross")
        }
        if abs(p.x) > 0.5 && p.y > 0.55 && p.z > 0.05 { return p.x < 0 ? "l1" : "r1" }
        if abs(p.x) > 0.5 && p.z < -0.05 { return p.x < 0 ? "l2" : "r2" }
        if abs(abs(p.x) - 0.467) < 0.03 && abs(p.y - 0.494) < 0.03 { return p.x < 0 ? "create" : "options" }
        if abs(abs(p.x) - 0.318) < 0.02 && abs(p.y) < 0.02 && p.z > 0.32 { return p.x < 0 ? "l3" : "r3" }
        if abs(p.x) < 0.01 && abs(p.y - 0.511) < 0.02 && s.x > 0.8 { return "lightbar" }
    }
    if mat == "1011" && abs(p.x) < 0.05 && p.y > 0.35 && p.z > 0.2 { return "touchpad" }
    return "body"
}

let root = SCNNode(); root.name = "PadModel"
var groups: [String: SCNNode] = [:]
var report: [String: Int] = [:]

scene.rootNode.enumerateHierarchy { n, _ in
    guard let g = n.geometry, let e = g.elements.first else { return }
    let mat = g.materials.first?.name ?? "?"
    let pos = floats(g.sources(for: .vertex)[0])
    let nor = floats(g.sources(for: .normal)[0])
    let uv  = floats(g.sources(for: .texcoord)[0])
    var tris: [UInt32] = []
    e.data.withUnsafeBytes { raw in
        let bpi = e.bytesPerIndex
        func at(_ i: Int) -> Int { bpi == 2 ? Int(raw.load(fromByteOffset: i * 2, as: UInt16.self)) : Int(raw.load(fromByteOffset: i * 4, as: UInt32.self)) }
        if e.primitiveType == .polygon {
            var cur = e.primitiveCount
            for f in 0..<e.primitiveCount {
                let k = at(f); let ids = (0..<k).map { at(cur + $0) }; cur += k
                for j in 1..<(k - 1) { tris += [UInt32(ids[0]), UInt32(ids[j]), UInt32(ids[j + 1])] }
            }
        } else { for i in 0..<(e.primitiveCount * 3) { tris.append(UInt32(at(i))) } }
    }
    // weld + union-find
    var keyMap: [SIMD3<Int32>: Int] = [:]; var weld = [Int](repeating: 0, count: pos.count)
    for (i, p) in pos.enumerated() {
        let k = SIMD3<Int32>(Int32((p[0] * 20000).rounded()), Int32((p[1] * 20000).rounded()), Int32((p[2] * 20000).rounded()))
        if let j = keyMap[k] { weld[i] = j } else { keyMap[k] = i; weld[i] = i }
    }
    var parent = Array(0..<pos.count)
    func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
    for t in stride(from: 0, to: tris.count, by: 3) {
        let a = find(weld[Int(tris[t])]), b = find(weld[Int(tris[t + 1])]), c = find(weld[Int(tris[t + 2])])
        parent[a] = c; parent[b] = c
    }
    var comps: [Int: Comp] = [:]
    for t in stride(from: 0, to: tris.count, by: 3) {
        let r = find(weld[Int(tris[t])])
        var c = comps[r] ?? Comp()
        for k in 0..<3 { let p = pos[Int(tris[t + k])]; let v = SIMD3(p[0], p[1], p[2]); c.mn = simd_min(c.mn, v); c.mx = simd_max(c.mx, v); c.tris.append(tris[t + k]) }
        comps[r] = c
    }
    // รวมชิ้นตามกลุ่ม (ปุ่มเดียวกัน + วัสดุเดียวกัน)
    var byGroup: [String: [UInt32]] = [:]
    for (_, c) in comps { let gname = classify(mat, c); byGroup[gname, default: []] += c.tris; report[gname, default: 0] += c.tris.count / 3 }
    for (gname, idx) in byGroup {
        var remap: [UInt32: UInt32] = [:]; var P: [SCNVector3] = [], N: [SCNVector3] = [], T: [CGPoint] = []; var I: [UInt32] = []
        for i in idx {
            if let m = remap[i] { I.append(m); continue }
            let m = UInt32(P.count); remap[i] = m; I.append(m)
            let p = pos[Int(i)], q = nor[Int(i)], u = uv[Int(i)]
            P.append(SCNVector3(p[0], p[1], p[2])); N.append(SCNVector3(q[0], q[1], q[2])); T.append(CGPoint(x: CGFloat(u[0]), y: CGFloat(u[1])))
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: P), SCNGeometrySource(normals: N), SCNGeometrySource(textureCoordinates: T)],
                              elements: [SCNGeometryElement(indices: I, primitiveType: .triangles)])
        let m = SCNMaterial(); m.name = mat; geo.materials = [m]
        let part = SCNNode(geometry: geo); part.name = "\(gname)-\(mat)"
        let grp = groups[gname] ?? { let x = SCNNode(); x.name = gname; groups[gname] = x; root.addChildNode(x); return x }()
        grp.addChildNode(part)
    }
}
// จุดหมุนของสติ๊ก = โคนสติ๊ก
for s in ["l3", "r3"] {
    guard let g = groups[s] else { continue }
    let (mn, mx) = g.boundingBox
    let pivot = SCNVector3((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z)
    for c in g.childNodes { c.position = SCNVector3(-pivot.x, -pivot.y, -pivot.z) }
    g.position = pivot
}
let out = SCNScene(); out.rootNode.addChildNode(root)
print(out.write(to: outURL, options: nil, delegate: nil, progressHandler: nil) ? "saved" : "FAILED")
for (k, v) in report.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v) tris") }
