// อ่านไฟล์ .glb (mesh เดียว) → ตำแหน่ง/normal/uv/index ที่ใส่ transform แล้ว + ภาพที่ฝังอยู่
import Foundation
import simd

struct GLBMesh { var pos: [SIMD3<Float>] = []; var nor: [SIMD3<Float>] = []; var uv: [SIMD2<Float>] = []; var idx: [UInt32] = [] }

func loadGLB(_ path: String, imagesTo dir: String?) -> GLBMesh {
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    func u32(_ o: Int) -> Int { Int(d.subdata(in: o..<o+4).withUnsafeBytes { $0.load(as: UInt32.self) }) }
    let jlen = u32(12)
    let json = try! JSONSerialization.jsonObject(with: d.subdata(in: 20..<20+jlen)) as! [String: Any]
    let binStart = 20 + jlen + 8
    let views = json["bufferViews"] as! [[String: Any]]
    let accs = json["accessors"] as! [[String: Any]]
    func view(_ i: Int) -> Data { let v = views[i]; let o = binStart + (v["byteOffset"] as? Int ?? 0); return d.subdata(in: o..<o + (v["byteLength"] as! Int)) }
    func floats(_ a: Int, _ n: Int) -> [[Float]] {
        let acc = accs[a]; let v = views[acc["bufferView"] as! Int]
        let base = binStart + (v["byteOffset"] as? Int ?? 0) + (acc["byteOffset"] as? Int ?? 0)
        let stride = v["byteStride"] as? Int ?? n * 4
        return (0..<(acc["count"] as! Int)).map { i in (0..<n).map { k in d.subdata(in: base + i*stride + k*4 ..< base + i*stride + k*4 + 4).withUnsafeBytes { $0.load(as: Float.self) } } }
    }
    func indices(_ a: Int) -> [UInt32] {
        let acc = accs[a]; let v = views[acc["bufferView"] as! Int]
        let base = binStart + (v["byteOffset"] as? Int ?? 0) + (acc["byteOffset"] as? Int ?? 0)
        let ct = acc["componentType"] as! Int; let sz = ct == 5125 ? 4 : (ct == 5123 ? 2 : 1)
        return (0..<(acc["count"] as! Int)).map { i in
            let o = base + i * sz
            switch sz { case 4: return d.subdata(in: o..<o+4).withUnsafeBytes { $0.load(as: UInt32.self) }
                        case 2: return UInt32(d.subdata(in: o..<o+2).withUnsafeBytes { $0.load(as: UInt16.self) })
                        default: return UInt32(d[o]) }
        }
    }
    // transform ของ node ที่มี mesh
    let nodes = json["nodes"] as! [[String: Any]]
    var M = matrix_identity_float4x4
    if let n = nodes.first(where: { $0["mesh"] != nil }) {
        let t = (n["translation"] as? [Double] ?? [0,0,0]).map(Float.init)
        let r = (n["rotation"] as? [Double] ?? [0,0,0,1]).map(Float.init)
        let s = (n["scale"] as? [Double] ?? [1,1,1]).map(Float.init)
        let q = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
        M = simd_float4x4(translation: SIMD3(t[0], t[1], t[2])) * simd_float4x4(q) * simd_float4x4(diagonal: SIMD4(s[0], s[1], s[2], 1))
    }
    let upper = simd_float3x3(SIMD3(M.columns.0.x, M.columns.0.y, M.columns.0.z), SIMD3(M.columns.1.x, M.columns.1.y, M.columns.1.z), SIMD3(M.columns.2.x, M.columns.2.y, M.columns.2.z))
    let nmat = upper.inverse.transpose

    var out = GLBMesh()
    let mesh = (json["meshes"] as! [[String: Any]])[0]
    for prim in mesh["primitives"] as! [[String: Any]] {
        let at = prim["attributes"] as! [String: Int]
        let base = UInt32(out.pos.count)
        for p in floats(at["POSITION"]!, 3) { let v = M * SIMD4(p[0], p[1], p[2], 1); out.pos.append(SIMD3(v.x, v.y, v.z)) }
        for q in floats(at["NORMAL"]!, 3) { out.nor.append(simd_normalize(nmat * SIMD3(q[0], q[1], q[2]))) }
        for t in floats(at["TEXCOORD_0"]!, 2) { out.uv.append(SIMD2(t[0], t[1])) }
        out.idx += indices(prim["indices"] as! Int).map { $0 + base }
    }
    if let dir, let imgs = json["images"] as? [[String: Any]] {
        for (i, im) in imgs.enumerated() { try? view(im["bufferView"] as! Int).write(to: URL(fileURLWithPath: "\(dir)/img\(i).png")) }
    }
    return out
}

extension simd_float4x4 {
    init(translation t: SIMD3<Float>) { self = matrix_identity_float4x4; columns.3 = SIMD4(t.x, t.y, t.z, 1) }
}
