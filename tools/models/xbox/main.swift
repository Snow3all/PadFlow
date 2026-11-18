// Usage: swiftc -O glb.swift main.swift -o xbake -framework SceneKit && ./xbake "xbox controller.glb" ../../../Resources/XboxModel.scn
// add a 3rd argument (a folder) to extract the embedded textures, then copy the base-color one to Resources/Textures/xbox_albedo.png
// แยกโมเดล Xbox (.glb) เป็นชิ้นตามปุ่ม หมุนให้หน้าจอยหันไป +z แล้วบันทึกเป็น .scn
import SceneKit
import simd
let a = CommandLine.arguments
let m = loadGLB(a[1], imagesTo: a.count > 3 ? a[3] : nil)   // อาร์กิวเมนต์ที่ 3 = โฟลเดอร์สำหรับภาพที่ฝังอยู่
let outURL = URL(fileURLWithPath: a[2])

var mn = SIMD3<Float>(repeating: 1e9), mx = SIMD3<Float>(repeating: -1e9)
for p in m.pos { mn = simd_min(mn, p); mx = simd_max(mx, p) }
let c = (mn + mx) / 2
let scale: Float = 2 / (mx.x - mn.x)
let tilt: Float = 0.253
func xf(_ p: SIMD3<Float>) -> SIMD3<Float> {
    let q = (p - c) * scale
    return SIMD3(q.x, q.y * cos(tilt) - q.z * sin(tilt), q.y * sin(tilt) + q.z * cos(tilt))
}
func xn(_ n: SIMD3<Float>) -> SIMD3<Float> { SIMD3(n.x, n.y * cos(tilt) - n.z * sin(tilt), n.y * sin(tilt) + n.z * cos(tilt)) }

// ชิ้นย่อยตามการเชื่อมต่อของ index (ไม่ weld)
var par = Array(0..<m.pos.count)
func f(_ x: Int) -> Int { var x = x; while par[x] != x { par[x] = par[par[x]]; x = par[x] }; return x }
for t in stride(from: 0, to: m.idx.count, by: 3) { let r0 = f(Int(m.idx[t])), r1 = f(Int(m.idx[t+1])), r2 = f(Int(m.idx[t+2])); par[r0] = r2; par[r1] = r2 }
struct Comp { var tris: [Int] = []; var mn = SIMD3<Float>(repeating: 1e9); var mx = SIMD3<Float>(repeating: -1e9) }
var comps: [Int: Comp] = [:]
for t in stride(from: 0, to: m.idx.count, by: 3) {
    let r = f(Int(m.idx[t])); var cc = comps[r] ?? Comp(); cc.tris.append(t)
    for k in 0..<3 { let p = m.pos[Int(m.idx[t+k])]; cc.mn = simd_min(cc.mn, p); cc.mx = simd_max(cc.mx, p) }
    comps[r] = cc
}

func near(_ p: SIMD3<Float>, _ x: Float, _ y: Float, _ r: Float) -> Bool { hypot(p.x - x, p.y - y) < r }
let dpadC = SIMD2<Float>(-0.0716, 0.134)
func classify(_ cc: Comp) -> String {
    let p = (cc.mn + cc.mx) / 2, s = cc.mx - cc.mn
    if near(p, -0.1590, 0.3417, 0.03) && s.x > 0.12 { return "l1" }
    if near(p, 0.2087, 0.3417, 0.03) && s.x > 0.12 { return "r1" }
    if near(p, -0.1879, 0.3023, 0.03) && p.z < 0.42 && s.x > 0.08 { return "l2" }
    if near(p, 0.2376, 0.3023, 0.03) && p.z < 0.42 && s.x > 0.08 { return "r2" }
    if p.z > 0.5 && s.x < 0.06 {
        if near(p, 0.2140, 0.2006, 0.026) { return "cross" }      // A
        if near(p, 0.2651, 0.2449, 0.026) { return "circle" }     // B
        if near(p, 0.1638, 0.2492, 0.026) { return "square" }     // X
        if near(p, 0.2151, 0.2964, 0.026) { return "triangle" }   // Y
        if near(p, -0.0288, 0.25, 0.02) { return "create" }       // View
        if near(p, 0.0782, 0.25, 0.02) { return "options" }       // Menu
    }
    if near(p, dpadC.x, dpadC.y, 0.06) && p.z > 0.54 && s.x < 0.12 { return "dpad" }
    if near(p, -0.1612, 0.255, 0.035) && p.z > 0.545 && s.x < 0.1 { return "l3" }
    if near(p, 0.1203, 0.150, 0.035) && p.z > 0.58 && s.x < 0.1 { return "r3" }
    return "body"
}

var groupsTris: [String: [Int]] = [:]
for (_, cc) in comps {
    let g = classify(cc)
    if g == "dpad" {
        for t in cc.tris {
            let ctr = (m.pos[Int(m.idx[t])] + m.pos[Int(m.idx[t+1])] + m.pos[Int(m.idx[t+2])]) / 3
            let dx = ctr.x - dpadC.x, dy = ctr.y - dpadC.y
            let name = hypot(dx, dy) < 0.012 ? "body" : (abs(dx) > abs(dy) ? (dx < 0 ? "left" : "right") : (dy > 0 ? "up" : "down"))
            groupsTris[name, default: []].append(t)
        }
    } else { groupsTris[g, default: []] += cc.tris }
}

let root = SCNNode(); root.name = "PadModel"
for (name, tris) in groupsTris.sorted(by: { $0.key < $1.key }) {
    var remap: [UInt32: UInt32] = [:]; var P: [SCNVector3] = [], N: [SCNVector3] = [], T: [CGPoint] = []; var I: [UInt32] = []
    for t in tris { for k in 0..<3 {
        let i = m.idx[t + k]
        if let r = remap[i] { I.append(r); continue }
        let r = UInt32(P.count); remap[i] = r; I.append(r)
        let p = xf(m.pos[Int(i)]), n = xn(m.nor[Int(i)]), u = m.uv[Int(i)]
        P.append(SCNVector3(p.x, p.y, p.z)); N.append(SCNVector3(n.x, n.y, n.z)); T.append(CGPoint(x: CGFloat(u.x), y: CGFloat(u.y)))
    } }
    let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: P), SCNGeometrySource(normals: N), SCNGeometrySource(textureCoordinates: T)],
                          elements: [SCNGeometryElement(indices: I, primitiveType: .triangles)])
    let mat = SCNMaterial(); mat.name = "xbox"; geo.materials = [mat]
    let part = SCNNode(geometry: geo); part.name = "\(name)-xbox"
    let grp = SCNNode(); grp.name = name; grp.addChildNode(part); root.addChildNode(grp)
    print("  \(name): \(tris.count) tris")
}
for s in ["l3", "r3"] {
    guard let g = root.childNode(withName: s, recursively: false) else { continue }
    let (bmn, bmx) = g.boundingBox
    let pivot = SCNVector3((bmn.x + bmx.x) / 2, (bmn.y + bmx.y) / 2, bmn.z)
    for ch in g.childNodes { ch.position = SCNVector3(-pivot.x, -pivot.y, -pivot.z) }
    g.position = pivot
}
let out = SCNScene(); out.rootNode.addChildNode(root)
print(out.write(to: outURL, options: nil, delegate: nil, progressHandler: nil) ? "saved" : "FAILED")
let (rmn, rmx) = root.boundingBox; print("bbox \(rmn) .. \(rmx)")
