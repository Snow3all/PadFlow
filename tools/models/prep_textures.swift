// Usage: swiftc -O prep_textures.swift -o prep -framework AppKit -framework CoreImage && ./prep <4k textures dir> ../../Resources/Textures
import AppKit
import CoreImage
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let ctx = CIContext()
for f in try! FileManager.default.contentsOfDirectory(atPath: src).sorted() {
    guard var img = CIImage(contentsOf: URL(fileURLWithPath: "\(src)/\(f)")) else { continue }
    let s = 2048.0 / img.extent.width
    img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
    var name = (f as NSString).deletingPathExtension
    if name.hasSuffix("_opacity") {
        img = img.applyingFilter("CIColorInvert"); name = name.replacingOccurrences(of: "_opacity", with: "_transp")
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let url = URL(fileURLWithPath: "\(dst)/\(name).jpg")
    try! ctx.writeJPEGRepresentation(of: img, to: url, colorSpace: cs, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.88])
    print(name)
}
