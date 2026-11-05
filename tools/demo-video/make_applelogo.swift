// 부팅 장면용 Apple 로고(SF Symbols apple.logo, 200pt, 흰색 0.96)를 PNG 로 만든다.
// 사용법: swift make_applelogo.swift <출력.png>
import Cocoa
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "applelogo.png"
let cfg = NSImage.SymbolConfiguration(pointSize: 200, weight: .regular)
let img = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let W = Int(img.size.width*2), H = Int(img.size.height*2)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = img.size
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let r = NSRect(origin: .zero, size: img.size)
img.draw(in: r); NSColor(calibratedWhite: 0.96, alpha: 1).set(); r.fill(using: .sourceAtop)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out)); print(W, H)
