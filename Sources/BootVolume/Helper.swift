import Foundation
import Security

/// 부팅음 도우미(루트 LaunchDaemon) 설치·제거와 부팅음 음량 재기.
///
/// 맥이 꺼지는 순간에 바꾼 시스템 음량은 NVRAM 에 늦게 기록돼 부팅음에 반영되지 않는다.
/// 그래서 도우미가 종료 신호를 받으면 NVRAM `SystemAudioVolumeExtension` 에 미리 재 둔 값을 직접 써 넣는다.
/// 이 값은 2바이트이고 형식이 공개돼 있지 않아, 그 음량으로 잠깐 맞춘 뒤 macOS 가 쓴 값을 읽어 온다.
extension Controller {
    static let helperDir = "/Library/Application Support/BootVolume"
    static let helperScript = helperDir + "/bootchime.sh"
    static let helperValue = helperDir + "/chime-value"
    static let helperPlist = "/Library/LaunchDaemons/top.oodot.bootchime.plist"
    static let helperLabel = "top.oodot.bootchime"

    func refreshHelper() {
        let fm = FileManager.default
        helperInstalled = fm.fileExists(atPath: Self.helperScript) && fm.fileExists(atPath: Self.helperPlist)
        if helperInstalled, let bundled = Bundle.main.url(forResource: "bootchime", withExtension: "sh") {
            helperOutdated = (try? Data(contentsOf: bundled)) != (try? Data(contentsOf: URL(fileURLWithPath: Self.helperScript)))
        } else {
            helperOutdated = false
        }
    }

    // MARK: 설치 · 제거

    /// 지금 실행 중인 이 앱의 서명 조건(designated requirement).
    /// 관리자 쪽에서 앱 폴더가 이 조건을 그대로 만족하는지 확인한 뒤에만 도우미를 복사한다.
    /// 누가 어떤 인증서로 빌드하든(임시 서명이면 cdhash) 그 빌드 자신이 기준이 된다.
    static var signRequirement: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req else { return nil }
        var str: CFString?
        guard SecRequirementCopyString(req, [], &str) == errSecSuccess, let str else { return nil }
        return str as String
    }

    /// 16진수 4자만 통과. 앱 설정(UserDefaults)은 같은 계정의 아무 프로그램이나 바꿀 수 있으므로
    /// 관리자 명령에 넣기 전에 반드시 거른다.
    static func safeHex(_ s: String?) -> String? {
        guard let s, s.range(of: "^[0-9a-f]{4}$", options: .regularExpression) != nil else { return nil }
        return s
    }

    func installHelper() {
        let app = Bundle.main.bundlePath
        let user = NSUserName()
        guard let req = Self.signRequirement, !req.contains("'"),
              !app.contains("'"), user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            message = "도우미를 설치하지 못했습니다."
            AppLog.error("설치 중단: 앱 서명을 읽지 못했거나 앱 경로·사용자 이름에 쓸 수 없는 글자가 있음")
            return
        }
        // 부팅음 값은 이 맥에서 잰 것만 쓴다(기종마다 뜻이 다를 수 있어 정해 둔 기본값은 없다)
        guard let hex = Self.safeHex(UserDefaults.standard.string(forKey: "chimeHex")) else {
            message = "부팅음 음량을 먼저 맞춰 주세요."
            AppLog.warn("설치 중단: 이 맥에서 잰 부팅음 값이 없음")
            return
        }
        // 관리자 권한으로 도는 스크립트. 바꿔치기를 막으려고
        // 1) 앱 서명을 확인하고 2) 관리자만 쓰는 임시 폴더로 복사한 뒤 3) 서명을 다시 확인하고 원본과 같은지 비교한다.
        // (앱 폴더는 내 계정 소유라 누구나 고칠 수 있다)
        runAdmin("""
        set -e
        APP='\(app)'
        REQ='\(req)'
        R="$APP/Contents/Resources"
        D='\(Self.helperDir)'
        P='\(Self.helperPlist)'
        codesign --verify --strict -R="$REQ" "$APP" || { echo "앱 서명 확인 실패" >&2; exit 3; }
        T=$(mktemp -d /var/root/bootvolume.XXXXXX)
        trap 'rm -rf "$T"' EXIT
        cp "$R/bootchime.sh" "$R/top.oodot.bootchime.plist" "$T/"
        codesign --verify --strict -R="$REQ" "$APP" || { echo "앱 서명 확인 실패" >&2; exit 3; }
        cmp -s "$T/bootchime.sh" "$R/bootchime.sh" && cmp -s "$T/top.oodot.bootchime.plist" "$R/top.oodot.bootchime.plist" \\
          || { echo "복사하는 동안 파일이 바뀜" >&2; exit 4; }
        mkdir -p "$D"
        chown root:wheel "$D"
        chmod 755 "$D"
        install -o root -g wheel -m 755 "$T/bootchime.sh" "$D/bootchime.sh"
        install -o root -g wheel -m 644 "$T/top.oodot.bootchime.plist" "$P"
        rm -f "$D/chime-value"
        echo \(hex) > "$D/chime-value"
        chown '\(user)' "$D/chime-value"
        chmod 644 "$D/chime-value"
        launchctl bootout system/\(Self.helperLabel) 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
          launchctl print system/\(Self.helperLabel) >/dev/null 2>&1 || break
          sleep 1
        done
        rm -f /usr/local/libexec/bootchime.sh
        launchctl bootstrap system "$P"
        """, success: "도우미 설치함 (음량 값 \(hex))", failure: "도우미를 설치하지 못했습니다.")
    }

    func uninstallHelper() {
        runAdmin("""
        launchctl bootout system/\(Self.helperLabel) 2>/dev/null
        rm -f '\(Self.helperPlist)' /usr/local/libexec/bootchime.sh
        rm -rf '\(Self.helperDir)'
        exit 0
        """, success: "도우미 지움", failure: "도우미를 지우지 못했습니다.")
    }

    /// 셸 스크립트를 관리자 권한으로 돌린다(암호 창). 몇 초 걸릴 수 있어 화면을 막지 않게 뒤에서 돌린다.
    /// 스크립트는 파일로 쓰지 않고 osascript 의 인자로 바로 넘긴다(파일이면 실행 전에 바꿔치기될 수 있다).
    func runAdmin(_ script: String, success: String, failure: String) {
        helperBusy = true
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = [
                "-e", "on run argv",
                "-e", "do shell script (item 1 of argv) with administrator privileges",
                "-e", "end run",
                script,
            ]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            try? p.run()
            p.waitUntilExit()
            let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let ok = p.terminationStatus == 0
            await MainActor.run {
                self.helperBusy = false
                // -128 은 암호 창에서 취소한 것
                let cancelled = errText.contains("-128")
                self.message = ok || cancelled ? nil : failure
                if ok { AppLog.info(success) }
                else if cancelled { AppLog.info("암호 창에서 취소함") }
                else { AppLog.error("\(failure) \(errText.trimmingCharacters(in: .whitespacesAndNewlines))") }
                self.checkHealth()
            }
        }
    }

    // MARK: 부팅음 음량

    /// NVRAM SystemAudioVolumeExtension 의 원래 바이트
    private func readExtension() -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        p.arguments = ["-x", "SystemAudioVolumeExtension"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?["SystemAudioVolumeExtension"] as? Data
    }

    /// 0.2초마다 읽어 조건이 맞을 때까지 기다린다(최대 4초).
    private func waitExtension(_ ok: (Data) -> Bool) async -> Data? {
        for _ in 0..<20 {
            if let b = readExtension(), b.count == 2, ok(b) { return b }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    /// 슬라이더를 놓았을 때 부른다. 음소거를 켠 채 음량만 그 값으로 맞춰 macOS 가 쓴 값을 읽고, 원래대로 되돌린다.
    /// 음소거 중에도 macOS 는 음량 값을 쓰고 둘째 바이트에 음소거 표시(0x80)만 더 붙인다(50 → 0a8f, 80 → 28bb).
    /// 그 표시만 빼면 음소거 없이 잰 값과 같다. 재는 동안 소리가 커지지 않는다(재생 중인 소리는 잠깐 음소거된다).
    func applyChimeVolume() {
        guard !measuring else { return }
        measuring = true
        let target = chimeVolume
        let saved = SystemVolume.snapshot()
        Task { @MainActor in
            defer {
                if let saved { SystemVolume.restore(saved) }
                measuring = false
                refreshVolume()
                checkHealth()
            }
            // 1) 음소거를 켜고 음량 0 으로 내린 뒤, macOS 가 쓸 시간(약 1.5초)을 기다려 기준 값을 읽는다
            SystemVolume.setMuted(true)
            SystemVolume.setLevel(0)
            try? await Task.sleep(for: .milliseconds(2000))
            guard let base = readExtension(), base.count == 2 else {
                message = "부팅음 음량을 재지 못했습니다."
                AppLog.error("부팅음 음량 \(target) 재기 실패: NVRAM 값을 읽지 못함")
                return
            }
            // 2) 음소거는 그대로 두고 음량만 목표로 올려, 기준과 달라진(음소거 표시가 붙은) 값을 기다린다
            SystemVolume.setLevel(target)
            guard let b = await waitExtension({ $0 != base && $0[1] & 0x80 != 0 }) else {
                message = "부팅음 음량을 재지 못했습니다."
                AppLog.error("부팅음 음량 \(target) 재기 실패: NVRAM 값이 바뀌지 않음")
                return
            }
            // 바뀐 직후 한 번 더 읽어 값이 자리를 잡았는지 보고, 음소거 표시를 뺀다
            try? await Task.sleep(for: .milliseconds(400))
            var settled = readExtension() ?? b
            if settled.count != 2 { settled = b }
            settled[settled.startIndex + 1] &= 0x7f
            let hex = settled.map { String(format: "%02x", $0) }.joined()
            UserDefaults.standard.set(hex, forKey: "chimeHex")
            message = nil
            AppLog.info("부팅음 음량 \(target) → 값 \(hex)")
            if helperInstalled {
                do {
                    try (hex + "\n").write(toFile: Self.helperValue, atomically: false, encoding: .utf8)
                } catch {
                    message = "도우미에 음량을 적지 못했습니다. 도우미를 다시 설치해 주세요."
                    AppLog.error("도우미 음량 값 파일에 쓰지 못함: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 지금 도우미가 쓰는 값
    enum HelperValue {
        case missing
        /// 16바이트를 넘어 도우미가 읽지 않는 파일(끌 때 부팅음 값을 쓰지 않는다)
        case tooBig(Int)
        case value(String)
    }

    /// 도우미 음량 값 파일. 도우미와 같은 규칙으로 크기부터 보고, 16바이트를 넘으면 읽지 않는다.
    var helperValue: HelperValue {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: Self.helperValue))?[.size] as? Int
        else { return .missing }
        if size > 16 { return .tooBig(size) }
        guard let s = try? String(contentsOfFile: Self.helperValue, encoding: .utf8) else { return .missing }
        return .value(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
