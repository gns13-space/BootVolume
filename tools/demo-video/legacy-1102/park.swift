import Cocoa
// park <pid> <save.txt> | unpark <save.txt>
let a = CommandLine.arguments
func wins(_ pid: Int32) -> [AXUIElement] { var v: CFTypeRef?; AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v); return (v as? [AXUIElement]) ?? [] }
func get(_ w: AXUIElement) -> CGRect { var p: CFTypeRef?, s: CFTypeRef?; var pt = CGPoint.zero, sz = CGSize.zero
  AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p); AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s)
  AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz); return CGRect(origin: pt, size: sz) }
func set(_ w: AXUIElement, _ p: CGPoint) { var q = p; AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &q)!) }
if a[1] == "park" {
  let pid = Int32(a[2])!; var lines: [String] = []
  for (i, w) in wins(pid).enumerated() { let r = get(w); lines.append("\(pid) \(i) \(r.origin.x) \(r.origin.y)"); set(w, CGPoint(x: 5000, y: 5000)); print("now", get(w)) }
  try! lines.joined(separator: "\n").write(toFile: a[3], atomically: true, encoding: .utf8)
} else {
  for l in ((try? String(contentsOfFile: a[2], encoding: .utf8)) ?? "").split(separator: "\n") {
    let f = l.split(separator: " "); let pid = Int32(f[0])!, i = Int(f[1])!; let ws = wins(pid); if i < ws.count { set(ws[i], CGPoint(x: Double(f[2])!, y: Double(f[3])!)) } }
}
