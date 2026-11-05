import Cocoa
// 사용법: drive <mode> <logfile>   mode = demo | restore60 | probe
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "probe"
let logPath = args.count > 2 ? args[2] : "/dev/null"
var log: [[String: Double]] = []
let t0 = Date()
func now() -> Double { Date().timeIntervalSince(t0) }
func rec(_ p: CGPoint, _ ev: Double = 0) { log.append(["t": now(), "x": Double(p.x), "y": Double(p.y), "ev": ev]) }
func cur() -> CGPoint { CGEvent(source: nil)!.location }
func post(_ type: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4*x*x*x : 1 - pow(-2*x+2, 3)/2 }
func glide(to b: CGPoint, _ dur: Double, drag: Bool = false) {
  let a = cur(); let n = max(1, Int(dur * 120))
  for i in 1...n { let k = ease(Double(i)/Double(n))
    let p = CGPoint(x: a.x + (b.x-a.x)*k, y: a.y + (b.y-a.y)*k)
    post(drag ? .leftMouseDragged : .mouseMoved, p); rec(p); usleep(useconds_t(1_000_000/120)) }
}
func wait(_ s: Double) { let end = Date().addingTimeInterval(s); while Date() < end { rec(cur()); usleep(8333) } }
func click(_ p: CGPoint) { post(.leftMouseDown, p); rec(p, 1); usleep(70_000); post(.leftMouseUp, p); rec(p, 2) }
func app() -> AXUIElement? { NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "top.oodot.bootvolume" }.map { AXUIElementCreateApplication($0.processIdentifier) } }
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, k as CFString, &v); return v }
func frame(_ e: AXUIElement) -> CGRect { var p = CGPoint.zero, s = CGSize.zero
  if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
  if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
  return CGRect(origin: p, size: s) }
func menuItem() -> CGRect? { guard let a = app(), let bar = attr(a, "AXExtrasMenuBar"), let kids = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement], let k = kids.first else { return nil }; return frame(k) }
func sliders() -> [AXUIElement] { guard let a = app(), let wins = attr(a, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
  var out: [AXUIElement] = []
  func walk(_ e: AXUIElement, _ d: Int) { if d > 30 { return }
    if (attr(e, kAXRoleAttribute) as? String) == kAXSliderRole { out.append(e) }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, d+1) } }
  for w in wins { walk(w, 0) }
  return out.sorted { frame($0).minY < frame($1).minY } }
func num(_ e: AXUIElement, _ k: String) -> Double { (attr(e, k) as? NSNumber)?.doubleValue ?? .nan }
func thumbX(_ f: CGRect, _ v: Double, _ lo: Double, _ hi: Double) -> CGFloat { let inset: CGFloat = 8; return f.minX + inset + CGFloat((v-lo)/(hi-lo)) * (f.width - 2*inset) }
func dragChime(to target: Double, slow: Double) -> String {
  let s = sliders(); guard s.count >= 3 else { return "slider not found (\(s.count))" }
  let c = s[2]; let f = frame(c); let v = num(c, kAXValueAttribute); let lo = 5.0, hi = 100.0
  let start = CGPoint(x: thumbX(f, v, lo, hi), y: f.midY)
  glide(to: start, 0.8); wait(0.3)
  post(.leftMouseDown, start); rec(start, 1); wait(0.12)
  glide(to: CGPoint(x: thumbX(f, target, lo, hi), y: f.midY), slow, drag: true); wait(0.2)
  let e = cur(); post(.leftMouseUp, e); rec(e, 2)
  return "chime slider \(f) value \(v) -> \(num(c, kAXValueAttribute))" }
func volumeDown() {
  for down in [true, false] {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
    let data1 = (1 << 16) | ((down ? 0xa : 0xb) << 8)  // NX_KEYTYPE_SOUND_DOWN = 1
    let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)!
    ev.cgEvent!.post(tap: .cghidEventTap); usleep(60_000) }
  log.append(["t": now(), "x": Double(cur().x), "y": Double(cur().y), "ev": 3])
}
func closePanel() { let k = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!; k.post(tap: .cghidEventTap); CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)!.post(tap: .cghidEventTap) }

switch mode {
case "probe":
  print("menu:", menuItem() as Any); print("sliders:", sliders().map { (frame($0), num($0, kAXValueAttribute)) })
case "demo":
  guard let m = menuItem() else { print("no menu item"); exit(1) }
  wait(1.5)
  glide(to: CGPoint(x: m.midX, y: m.midY), 1.1); wait(0.3); click(CGPoint(x: m.midX, y: m.midY))
  wait(1.2)
  print(dragChime(to: 80, slow: 1.6))
  wait(5.2)
  glide(to: CGPoint(x: m.midX - 260, y: m.midY + 520), 1.0); wait(0.4)
  closePanel(); log.append(["t": now(), "x": Double(cur().x), "y": Double(cur().y), "ev": 4]); wait(1.2)
  volumeDown(); wait(2.8)
case "restore":
  let target = Double(args.count > 3 ? args[3] : "60")!
  guard let m = menuItem() else { print("no menu item"); exit(1) }
  if sliders().count < 3 { click(CGPoint(x: m.midX, y: m.midY)); wait(1.0) }
  print(dragChime(to: target, slow: 0.6)); wait(3.5); closePanel()
default: break
}
let data = try! JSONSerialization.data(withJSONObject: log)
try! data.write(to: URL(fileURLWithPath: logPath))
