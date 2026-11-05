import CoreGraphics
import Foundation
import AppKit
func mkey(_ k: Int, _ down: Bool) { let f = down ? 0xa00 : 0xb00; let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(f)), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (k<<16)|f, data2: -1); e?.cgEvent?.post(tap: .cghidEventTap) }
let a = CommandLine.arguments
func post(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
func move(_ from: CGPoint, _ to: CGPoint, _ dur: Double, drag: Bool) {
  let n = max(1, Int(dur*60))
  for i in 1...n { let t = Double(i)/Double(n); let e = t<0.5 ? 2*t*t : 1-pow(-2*t+2,2)/2
    post(drag ? .leftMouseDragged : .mouseMoved, CGPoint(x: from.x+(to.x-from.x)*e, y: from.y+(to.y-from.y)*e)); usleep(16666) }
}
var cur = CGEvent(source: nil)!.location
var i = 1
while i < a.count {
  let c = a[i]
  switch c {
  case "move": let p = CGPoint(x: Double(a[i+1])!, y: Double(a[i+2])!); move(cur, p, Double(a[i+3])!, drag:false); cur = p; i += 4
  case "click": post(.leftMouseDown, cur); usleep(80000); post(.leftMouseUp, cur); i += 1
  case "drag": let p = CGPoint(x: Double(a[i+1])!, y: Double(a[i+2])!); post(.leftMouseDown, cur); usleep(150000); move(cur, p, Double(a[i+3])!, drag:true); cur = p; usleep(150000); post(.leftMouseUp, cur); i += 4
  case "voldown": mkey(1,true); usleep(50000); mkey(1,false); i += 1
  case "wait": usleep(useconds_t(Double(a[i+1])!*1e6)); i += 2
  default: i += 1
  }
}
