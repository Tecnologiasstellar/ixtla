// Cuts the rug out of a photo with macOS Vision (no upload, no service).
// Build once:  swiftc -O cutout.swift -o cutout
// Use:         ./cutout IMG_1234.HEIC out.png 1600   then   cwebp -q 84 -alpha_q 100 -m 6 out.png -o img/1234.webp
import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: cutout in out [maxDim]"); exit(2) }
let inURL = URL(fileURLWithPath: a[1]), outURL = URL(fileURLWithPath: a[2])
let maxDim = a.count > 3 ? CGFloat(Double(a[3])!) : 1600

guard var img = CIImage(contentsOf: inURL, options: [.applyOrientationProperty: true]) else { print("cannot read"); exit(1) }
let s = min(1, maxDim / max(img.extent.width, img.extent.height))
if s < 1 {
  let f = CIFilter.lanczosScaleTransform(); f.inputImage = img; f.scale = Float(s); f.aspectRatio = 1
  img = f.outputImage!
}
img = img.transformed(by: CGAffineTransform(translationX: -img.extent.origin.x, y: -img.extent.origin.y)).cropped(to: CGRect(x: 0, y: 0, width: floor(img.extent.width), height: floor(img.extent.height)))

let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: img, options: [:])
try handler.perform([req])
guard let res = req.results?.first else { print("no foreground found"); exit(1) }
let maskBuf = try res.generateScaledMaskForImage(forInstances: res.allInstances, from: handler)
let mask = CIImage(cvPixelBuffer: maskBuf)
let maskScaled = mask.transformed(by: CGAffineTransform(scaleX: img.extent.width / mask.extent.width, y: img.extent.height / mask.extent.height))

let blend = CIFilter.blendWithMask()
blend.inputImage = img
blend.backgroundImage = CIImage(color: CIColor.clear).cropped(to: img.extent)
blend.maskImage = maskScaled
guard let out = blend.outputImage else { exit(1) }

let ctx = CIContext()
guard let cg = ctx.createCGImage(out, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { exit(1) }
let w = cg.width, h = cg.height
guard let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { exit(1) }
let bpr = cg.bytesPerRow
var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h { for x in 0..<w { if p[y*bpr + x*4 + 3] > 8 { if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; if y > maxY { maxY = y } } } }
guard maxX >= 0 else { print("empty mask"); exit(1) }
let pad = 10
let x0 = max(0, minX - pad), y0 = max(0, minY - pad)
let rect = CGRect(x: x0, y: y0, width: min(w, maxX + pad + 1) - x0, height: min(h, maxY + pad + 1) - y0)
guard let cropped = cg.cropping(to: rect) else { exit(1) }
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, cropped, nil)
CGImageDestinationFinalize(dest)
print("\(outURL.lastPathComponent) \(Int(rect.width))x\(Int(rect.height)) instances=\(res.allInstances.count)")
