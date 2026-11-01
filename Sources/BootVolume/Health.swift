import Foundation

/// 도우미와 부팅음 상태 점검. 앱이 켜질 때, 1분마다, 패널·설정을 열 때 돈다.
struct Problem: Hashable, Identifiable {
    enum Level { case warn, error }
    let level: Level
    let text: String
    /// 지나간 일(지난번 끄기·부팅 뒤 오류)이라 '확인'으로 치울 수 있는 것.
    /// 지금 상태(미설치·안 돎 등)는 고치면 저절로 사라지므로 치울 수 없다.
    var event = false
    var id: String { text }
}

extension Controller {
    func checkHealth() {
        var p: [Problem] = []
        let fm = FileManager.default

        refreshChime()  // helperInstalled · helperOutdated · chimeOn 갱신

        if !chimeOn {
            p.append(.init(level: .warn, text: "부팅음이 꺼져 있습니다."))
        }

        if !helperInstalled {
            p.append(.init(level: .error, text: "도우미가 설치되어 있지 않습니다."))
        } else {
            if helperOutdated {
                p.append(.init(level: .warn, text: "도우미를 새 버전으로 업데이트해야 합니다."))
            }
            if !helperRunning() {
                p.append(.init(level: .error, text: "도우미가 돌고 있지 않습니다. 도우미를 다시 설치해 주세요."))
            }
            let want = UserDefaults.standard.string(forKey: "chimeHex")
            switch helperValue {
            case .missing:
                p.append(.init(level: .error, text: "도우미의 음량 값 파일을 읽지 못했습니다. 끌 때 부팅음 값을 쓰지 못합니다. 도우미를 다시 설치해 주세요."))
            case .tooBig(let size):
                p.append(.init(level: .error, text: "도우미의 음량 값 파일이 너무 큽니다(\(size)바이트, 정상은 5바이트). 도우미가 읽지 않아 끌 때 부팅음 값을 쓰지 못합니다. 부팅음 음량을 다시 맞추면 고쳐집니다."))
            case .value(let v) where Self.safeHex(v) == nil:
                let shown = String(v.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16))
                p.append(.init(level: .error, text: "도우미의 음량 값이 잘못되어 있습니다(\(shown)). 끌 때 부팅음 값을 쓰지 못합니다. 부팅음 음량을 다시 맞추면 고쳐집니다."))
            case .value(let v) where want != nil && v != want:
                p.append(.init(level: .warn, text: "도우미의 음량 값이 앱 설정과 다릅니다. 부팅음 음량을 한 번 다시 맞춰 주세요."))
            default: break
            }
            p.append(contentsOf: checkLastShutdown())
        }

        if !fm.fileExists(atPath: AppLog.helperURL.path), helperInstalled {
            p.append(.init(level: .warn, text: "도우미 기록 파일이 없습니다."))
        }

        // '확인'한 지나간 일은 이번 부팅 동안 다시 띄우지 않는다
        let dismissed = dismissedEvents()
        p.removeAll { $0.event && dismissed.contains($0.text) }

        lastHealthCheck = Date()
        if p != problems {
            for x in p where !problems.contains(x) {
                x.level == .error ? AppLog.error("점검: \(x.text)") : AppLog.warn("점검: \(x.text)")
            }
            if p.isEmpty && !problems.isEmpty { AppLog.info("점검: 모두 정상") }
            problems = p
        }
    }

    // MARK: 확인

    private var bootKey: String { String(Int(Self.bootTimeValue())) }

    private func dismissedEvents() -> Set<String> {
        let d = UserDefaults.standard
        guard d.string(forKey: "dismissedBoot") == bootKey else { return [] }
        return Set(d.stringArray(forKey: "dismissed") ?? [])
    }

    func dismiss(_ items: [Problem]) {
        let targets = items.filter(\.event)
        guard !targets.isEmpty else { return }
        let d = UserDefaults.standard
        var set = dismissedEvents()
        for x in targets { set.insert(x.text); AppLog.info("확인함: \(x.text)") }
        d.set(bootKey, forKey: "dismissedBoot")
        d.set(Array(set), forKey: "dismissed")
        problems.removeAll { $0.event && set.contains($0.text) }
    }

    private func helperRunning() -> Bool {
        let out = run("/bin/launchctl", ["print", "system/\(Self.helperLabel)"])
        return out.contains("state = running")
    }

    /// 도우미 기록을 보고 지난번 끌 때 값을 제대로 써 넣었는지 본다.
    private func checkLastShutdown() -> [Problem] {
        let lines = AppLog.tail(AppLog.helperURL, lines: 200)
        guard !lines.isEmpty else { return [] }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func date(_ l: String) -> Date? { l.count >= 19 ? f.date(from: String(l.prefix(19))) : nil }

        var out: [Problem] = []
        let boot = Date(timeIntervalSince1970: Self.bootTimeValue())

        // 이번 부팅 이후의 오류
        for l in lines where l.contains("오류:") {
            if let d = date(l), d >= boot.addingTimeInterval(-300) {
                out.append(.init(level: .error, text: "도우미: " + String(l.dropFirst(20)), event: true))
            }
        }

        // 이번 부팅 직전에 도우미가 '종료' 를 남겼는지. 도우미가 그 전부터 돌고 있었을 때만 따진다.
        // 이번 부팅 '전' 기록만 본다. 부팅 뒤의 '종료' 는 도우미를 다시 설치할 때 옛 도우미가 남긴 것이라 상관없다.
        let before = lines.filter { (date($0) ?? .distantFuture) < boot }
        let startedBefore = before.contains { $0.hasSuffix("시작") }
        if startedBefore {
            if let lw = before.last(where: { $0.contains("종료 →") }), let d = date(lw),
               boot.timeIntervalSince(d) < 600 {
                // 써 넣은 값과 마지막으로 읽은 값이 같은지
                let written = lw.components(separatedBy: "→ ").last?.components(separatedBy: " ").first ?? ""
                if let lastLine = before.last(where: { $0.contains("마지막 값:") }),
                   let ld = date(lastLine), ld >= d {
                    let read = lastLine.components(separatedBy: "마지막 값: ").last ?? ""
                    if Self.nvramBytes(written) != Self.nvramBytes(read) {
                        out.append(.init(level: .warn, text: "지난번 끌 때 써 넣은 값(\(written))이 다른 값(\(read))으로 덮였습니다.", event: true))
                    }
                }
            } else {
                out.append(.init(level: .warn, text: "지난번 끌 때 도우미가 값을 써 넣지 못했습니다. 전원 버튼으로 강제로 껐다면 정상입니다.", event: true))
            }
        }
        return out
    }

    /// nvram 이 찍은 값("%a2%18", "(;")을 바이트로
    static func nvramBytes(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var chars = Array(s.utf8)[...]
        while let c = chars.first {
            if c == UInt8(ascii: "%"), chars.count >= 3,
               let b = UInt8(String(decoding: chars.dropFirst().prefix(2), as: UTF8.self), radix: 16) {
                out.append(b); chars = chars.dropFirst(3)
            } else {
                out.append(c); chars = chars.dropFirst()
            }
        }
        return out
    }

    static func bootTimeValue() -> Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec)
    }

    func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
