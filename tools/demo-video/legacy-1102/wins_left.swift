import Cocoa
let skip: Set<String> = ["Dock","Window Server","WindowManager","Control Center","SystemUIServer","BootVolume","알림 센터","제어 센터","Finder","screencaptureui"]
var left: [String] = []
for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as! [[String:Any]] {
  guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
  let o = w[kCGWindowOwnerName as String] as? String ?? ""; if skip.contains(o) { continue }
  let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]; if (b["Width"] ?? 0) < 50 { continue }
  left.append(String(w[kCGWindowOwnerPID as String] as! Int)) }
print(Set(left).joined(separator: ","))
