import Cocoa
let mode = CommandLine.arguments[1]; let file = CommandLine.arguments[2]
if mode == "hide" {
  var hid: [String] = []
  for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && !a.isHidden {
    if a.hide() { hid.append(String(a.processIdentifier)) } }
  try! hid.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
  RunLoop.current.run(until: Date().addingTimeInterval(0.8))
  for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular && !a.isHidden { if a.hide() == false { print("못 숨김:", a.localizedName ?? "") } }
} else {
  let pids = ((try? String(contentsOfFile: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { Int32($0) }
  for p in pids { NSRunningApplication(processIdentifier: p)?.unhide() }
}
