import Foundation

/// 앱 기록. ~/Library/Logs/BootVolume.log 에 "YYYY-MM-DD HH:mm:ss [종류] 내용" 으로 한 줄씩 남긴다.
enum AppLog {
    enum Kind: String { case info = "정보", warn = "경고", error = "오류" }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BootVolume.log")
    static let helperURL = URL(fileURLWithPath: "/var/log/bootchime.log")

    private static let maxBytes = 256 * 1024

    static func write(_ kind: Kind, _ text: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) [\(kind.rawValue)] \(text)\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        h.write(Data(line.utf8))
        trimIfNeeded()
    }

    static func info(_ t: String) { write(.info, t) }
    static func warn(_ t: String) { write(.warn, t) }
    static func error(_ t: String) { write(.error, t) }

    /// 너무 커지면 뒤쪽 절반만 남긴다
    private static func trimIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        var tail = data.suffix(maxBytes / 2)
        if let nl = tail.firstIndex(of: UInt8(ascii: "\n")) { tail = tail[(nl + 1)...] }
        try? Data(tail).write(to: url)
    }

    /// 마지막 n 줄
    static func tail(_ file: URL, lines n: Int = 400) -> [String] {
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Array(s.split(separator: "\n", omittingEmptySubsequences: true).suffix(n).map(String.init))
    }
}
