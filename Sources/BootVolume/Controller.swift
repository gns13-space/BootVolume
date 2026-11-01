import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class Controller: ObservableObject {
    static weak var shared: Controller?

    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var loginVolume: Int { didSet { d.set(loginVolume, forKey: "loginVolume") } }
    @Published var currentVolume: Int = 0
    @Published var launchAtLogin = false
    @Published var chimeOn = true
    @Published var helperInstalled = false
    @Published var helperOutdated = false
    /// 부팅음 음량(%). 실제로 써 넣는 값은 chime-value 파일의 2바이트.
    @Published var chimeVolume: Int { didSet { d.set(chimeVolume, forKey: "chimeVolume") } }
    @Published var measuring = false
    /// 켜면 로그인 후 음량 대신 끄기 직전 음량으로 되돌린다
    @Published var restorePrevious: Bool { didSet { d.set(restorePrevious, forKey: "restorePrevious") } }
    /// 로그인 음량 맞추기가 끝난 뒤부터 음량을 기억한다(부팅 직후 값을 '끄기 전 음량'으로 잘못 적지 않게)
    private var tracking = false
    /// 음량 정밀 모드: 슬라이더 1 단위(끄면 5 단위)
    @Published var precise: Bool { didSet { d.set(precise, forKey: "precise") } }
    @Published var helperBusy = false
    @Published var problems: [Problem] = []
    @Published var lastHealthCheck: Date?
    @Published var lastLogin: Date? { didSet { d.set(lastLogin, forKey: "lastLogin") } }
    @Published var lastShutdown: Date? { didSet { d.set(lastShutdown, forKey: "lastShutdown") } }
    @Published var message: String?

    /// 슬라이더를 움직이는 동안 폴링이 값을 되돌리지 않게 한다.
    var editingCurrent = false
    private var timer: Timer?

    init() {
        d.register(defaults: ["enabled": true, "loginVolume": 0, "chimeVolume": 60, "precise": false, "restorePrevious": false, "pendingLogin": true])
        enabled = d.bool(forKey: "enabled")
        loginVolume = d.integer(forKey: "loginVolume")
        chimeVolume = d.integer(forKey: "chimeVolume")
        precise = d.bool(forKey: "precise")
        restorePrevious = d.bool(forKey: "restorePrevious")
        lastLogin = d.object(forKey: "lastLogin") as? Date
        lastShutdown = d.object(forKey: "lastShutdown") as? Date
        Controller.shared = self

        refreshVolume()
        // 처음 한 번은 로그인 시 열기를 켜 둔다. 그 뒤로는 사용자가 정한 대로.
        if !d.bool(forKey: "didSetupLogin") {
            try? SMAppService.mainApp.register()
            d.set(true, forKey: "didSetupLogin")
        }
        refreshLaunchAtLogin()
        refreshChime()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Controller.shared?.applyShutdown() }
        }

        let t = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Controller.shared?.refreshVolume() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 도우미 점검은 문제가 생기는 때(켜질 때·잠자기에서 깰 때)와 패널·설정을 열 때만.
        // 주기적으로 돌리지 않는다(점검 한 번에 nvram·launchctl 을 서너 번 띄운다).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Controller.shared?.checkHealth() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkHealth() }
        AppLog.info("앱 시작 (버전 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))")

        // 시험용: 끌 때 알림을 흉내 낸다 (open -a BootVolume --args --test-poweroff)
        if CommandLine.arguments.contains("--test-poweroff") {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willPowerOffNotification, object: nil)
            return
        }

        // 시험용: 지금 부팅음 음량으로 재 보고 결과를 남긴다 (--args --test-measure)
        if CommandLine.arguments.contains("--test-measure") {
            applyChimeVolume()
            return
        }

        applyLoginIfNeeded()

        // 처음 설치했을 때: 기본 부팅음 음량(60)을 이 맥에서 재 둔다. 로그인 음량 맞추기(0~6초)가 끝난 뒤에.
        if d.string(forKey: "chimeHex") == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.applyChimeVolume() }
        }
    }

    // MARK: 로그인 · 종료

    /// 새로 부팅했거나 지난번에 로그아웃/종료로 끝났을 때만 로그인 음량을 적용한다.
    /// 세션 중에 앱만 다시 열었을 때는 건드리지 않는다.
    private func applyLoginIfNeeded() {
        let boot = Self.bootTime()
        let newSession = d.bool(forKey: "pendingLogin") || abs(d.double(forKey: "bootTime") - boot) > 1
        d.set(boot, forKey: "bootTime")
        d.set(false, forKey: "pendingLogin")
        guard enabled, newSession else { tracking = true; return }
        let target = restorePrevious ? (d.object(forKey: "lastVolume") as? Int ?? loginVolume) : loginVolume
        AppLog.info("로그인: 음량을 \(target)(으)로 맞춤" + (restorePrevious ? " (끄기 전 음량)" : ""))
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            guard let v = SystemVolume.get() else { return }
            if v != target { AppLog.warn("로그인: 음량을 \(target)(으)로 맞췄지만 지금 \(v) 입니다") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.tracking = true }
        // 바로 내리고, 오디오 장치가 늦게 잡히거나 시스템이 저장값으로 되돌리는 경우를 위해 몇 번 더 내린다.
        for delay in [0.0, 1, 3, 6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.enabled else { return }
                SystemVolume.set(target)
                self.lastLogin = Date()
                self.refreshVolume()
            }
        }
    }

    private var shutdownApplied = false

    func applyShutdown() {
        guard !shutdownApplied else { return }
        shutdownApplied = true
        if tracking, !measuring, let v = SystemVolume.get() { d.set(v, forKey: "lastVolume") }
        AppLog.info("끄기: 지금 음량 \(SystemVolume.get().map(String.init) ?? "?") 기억, 부팅음은 도우미가 써 넣음")
        // 부팅음은 루트 도우미(Resources/bootchime.sh)가 NVRAM 에 직접 써 넣는다.
        // 여기서 시스템 음량을 올리면 NVRAM 에 늦게 기록돼 소용이 없고, 로그인 직후 음량만 커진다.
        d.set(true, forKey: "pendingLogin")
        lastShutdown = Date()
        d.synchronize()
    }

    private static func bootTime() -> Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec)
    }

    // MARK: 지금 음량

    func refreshVolume() {
        guard !editingCurrent, let v = SystemVolume.get() else { return }
        if v != currentVolume { currentVolume = v }
        if tracking, !measuring, d.integer(forKey: "lastVolume") != v || d.object(forKey: "lastVolume") == nil {
            d.set(v, forKey: "lastVolume")
        }
    }

    func setCurrent(_ v: Int) {
        currentVolume = v
        SystemVolume.set(v)
    }

    // MARK: 로그인 시 열기

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = "로그인 시 열기를 바꾸지 못했습니다. 앱이 응용 프로그램 폴더에 있는지 확인해 주세요."
            AppLog.error("로그인 시 열기 변경 실패: \(error.localizedDescription)")
        }
        refreshLaunchAtLogin()
    }

    // MARK: 부팅음

    func nvram(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// 부팅음을 막는 값은 둘이다.
    /// - StartupMute=%01 (시스템 설정의 '시동 시 사운드 재생' 끔)
    /// - SystemAudioVolume=%80 (옛 방식의 음소거 고정값. macOS 가 다시 쓰지 않아 한 번 박히면 계속 남는다)
    func refreshChime() {
        let mute = nvram(["StartupMute"]).contains("%01")
        let legacy = nvram(["SystemAudioVolume"]).contains("\t%80")
        chimeOn = !mute && !legacy
        refreshHelper()
    }

    /// nvram 은 관리자 권한이 필요해 암호 창이 뜬다.
    func setChime(_ on: Bool) {
        let cmd = on
            ? "nvram StartupMute=%00; nvram -d SystemAudioVolume 2>/dev/null || true"
            : "nvram StartupMute=%01"
        runAdmin(cmd, success: on ? "부팅음 켬" : "부팅음 끔", failure: "부팅음 설정을 바꾸지 못했습니다.")
    }

    // MARK: 표시

    static func format(_ date: Date?) -> String {
        guard let date else { return "아직 없음" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "오늘 HH:mm" : "M월 d일 HH:mm"
        return f.string(from: date)
    }
}
