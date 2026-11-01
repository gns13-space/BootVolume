import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 로그아웃·재시작·종료로 앱이 닫힐 때도 끄기 처리(지금 음량 기억)를 한다.
    /// (willPowerOff 알림을 놓쳤을 때의 보험. 부팅음 값은 도우미가 따로 써 넣는다)
    func applicationWillTerminate(_ notification: Notification) {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent,
              let reason = ev.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        else { return }
        let powerOff: [OSType] = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog,
                                  kAEShowShutdownDialog, kAERestart, kAEShutDown].map { OSType($0) }
        if powerOff.contains(reason) {
            MainActor.assumeIsolated { Controller.shared?.applyShutdown() }
        }
    }
}

@main
struct BootVolumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var c = Controller()

    var body: some Scene {
        MenuBarExtra {
            PanelView(c: c)
                .frame(width: 280)
        } label: {
            Image(systemName: c.enabled ? "speaker.wave.2.fill" : "speaker.slash")
        }
        .menuBarExtraStyle(.window)

        // macOS 설정 창(제목 막대에 탭이 붙는 창)
        Settings {
            SettingsView(c: c)
        }
    }
}

struct PanelView: View {
    @ObservedObject var c: Controller
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        main
        .padding(14)
        .background(RoundedWindow(radius: 16))
        .onAppear {
            c.refreshVolume()
            c.refreshLaunchAtLogin()
            c.refreshChime()
            c.checkHealth()
        }
    }

    private func openLogs() {
        UserDefaults.standard.set("logs", forKey: "settingsTab")
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private var step: Double { c.precise ? 1 : 5 }

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("BootVolume").font(.headline)
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("설정")
                Toggle("", isOn: $c.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            VolumeRow(title: "지금 음량", value: Binding(
                get: { c.currentVolume },
                set: { c.setCurrent($0) }
            ), step: step, onEditing: { c.editingCurrent = $0 })

            Divider()

            VolumeRow(title: "로그인 후", value: $c.loginVolume, step: step)
                .disabled(!c.enabled || c.restorePrevious)
                .opacity(c.enabled && !c.restorePrevious ? 1 : 0.45)

            VolumeRow(title: "부팅음", value: $c.chimeVolume, range: 5...100, step: step,
                      busy: c.measuring,
                      onEditing: { if !$0 { c.applyChimeVolume() } },
                      onTyped: { c.applyChimeVolume() })
                .disabled(!c.chimeOn || c.measuring)
                .opacity(c.chimeOn ? 1 : 0.45)

            Divider()

            SwitchRow(title: "부팅음 켜기", isOn: Binding(
                get: { c.chimeOn },
                set: { c.setChime($0) }
            ))

            SwitchRow(title: "로그인 시 열기", isOn: Binding(
                get: { c.launchAtLogin },
                set: { c.setLaunchAtLogin($0) }
            ))

            SwitchRow(title: "끄기 전 음량으로 되돌리기", isOn: $c.restorePrevious)
                .disabled(!c.enabled)
                .opacity(c.enabled ? 1 : 0.45)

            if !c.helperInstalled || c.helperOutdated {
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.helperInstalled
                         ? "부팅음 도우미를 새 버전으로 바꿔야 합니다."
                         : "부팅음 도우미를 설치해야 부팅음이 납니다. 관리자 암호가 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(c.helperInstalled ? "도우미 업데이트" : "도우미 설치") { c.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(c.helperBusy)
                }
            }

            if let m = c.message {
                Text(m)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("도우미")
                    Spacer()
                    Circle()
                        .fill(c.problems.contains { $0.level == .error } ? Color.red
                              : c.problems.isEmpty ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(c.problems.isEmpty ? "정상" : "확인 필요 \(c.problems.count)")
                }
                .contentShape(Rectangle())
                .onTapGesture { openLogs() }
                .help("눌러서 기록 보기")
                HStack {
                    Text("마지막 로그인")
                    Spacer()
                    Text(Controller.format(c.lastLogin)).monospacedDigit()
                }
                HStack {
                    Text("마지막 끄기")
                    Spacer()
                    Text(Controller.format(c.lastShutdown)).monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                if c.helperInstalled {
                    Button("도우미 지우기") { c.uninstallHelper() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(c.helperBusy)
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var c: Controller

    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(c: c)
                .frame(width: 420)
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag("general")
            LogsSettings(c: c)
                .frame(width: 560, height: 480)
                .tabItem { Label("기록", systemImage: "list.bullet.rectangle") }
                .tag("logs")
            AboutSettings()
                .frame(width: 420)
                .tabItem { Label("정보", systemImage: "info.circle") }
                .tag("about")
        }
    }
}

struct GeneralSettings: View {
    @ObservedObject var c: Controller

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $c.precise) {
                    Text("음량 정밀 모드")
                    Text("켜면 슬라이더가 1씩, 끄면 5씩 움직입니다.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LogsSettings: View {
    @ObservedObject var c: Controller
    @State private var source = "app"
    @State private var lines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 상태
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("상태").font(.headline)
                    Spacer()
                    if let d = c.lastHealthCheck {
                        Text("마지막 점검 \(Controller.format(d))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("지금 점검") { c.checkHealth(); load() }
                        .controlSize(.small)
                }
                if c.problems.isEmpty {
                    Label("모두 정상입니다.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(c.problems) { p in
                        HStack(alignment: .firstTextBaseline) {
                            Label {
                                Text(p.text).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: p.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(p.level == .error ? .red : .orange)
                            }
                            Spacer()
                            if p.event {
                                Button("확인") { c.dismiss([p]) }
                                    .controlSize(.small)
                            }
                        }
                    }
                    if c.problems.filter(\.event).count > 1 {
                        Button("모두 확인") { c.dismiss(c.problems) }
                            .controlSize(.small)
                    }
                }
            }

            Divider()

            // 기록
            HStack {
                Picker("", selection: $source) {
                    Text("앱").tag("app")
                    Text("도우미").tag("helper")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                Spacer()
                Button("새로 고침", action: load).controlSize(.small)
                Button("Finder에서 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                .controlSize(.small)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if lines.isEmpty {
                            Text("기록이 없습니다.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                            Text(l)
                                .foregroundStyle(color(l))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                .onChange(of: lines) { _, new in
                    if !new.isEmpty { proxy.scrollTo(new.count - 1, anchor: .bottom) }
                }
            }
        }
        .padding(20)
        .onAppear { c.checkHealth(); load() }
        .onChange(of: source) { _, _ in load() }
    }

    private var file: URL { source == "app" ? AppLog.url : AppLog.helperURL }

    private func load() { lines = AppLog.tail(file) }

    private func color(_ l: String) -> Color {
        if l.contains("[오류]") || l.contains("오류:") { return .red }
        if l.contains("[경고]") { return .orange }
        return .primary
    }
}

struct AboutSettings: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Text("BootVolume").font(.title3.weight(.semibold))
            Text("버전 \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct VolumeRow: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Double> = 0...100
    var step: Double = 5
    var busy = false
    var onEditing: (Bool) -> Void = { _ in }
    /// 숫자를 직접 입력해 바꿨을 때
    var onTyped: () -> Void = {}

    @State private var typing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 64, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: range,
                step: step,
                onEditingChanged: onEditing
            )
            .controlSize(.small)
            Group {
                if busy {
                    ProgressView().controlSize(.mini)
                } else if typing {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { typing = false }
                        .onChange(of: focused) { _, now in if !now { commit() } }
                } else {
                    Text("\(value)")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: startTyping)
                        .help("눌러서 숫자로 입력")
                }
            }
            .monospacedDigit()
            .frame(width: 32, alignment: .trailing)
        }
    }

    private func startTyping() {
        text = "\(value)"
        typing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        guard typing else { return }
        typing = false
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
        let clamped = min(max(n, Int(range.lowerBound)), Int(range.upperBound))
        guard clamped != value else { return }
        value = clamped
        onTyped()
    }
}

/// 글은 왼쪽, 스위치는 오른쪽 끝 (맨 위 BootVolume 스위치와 줄을 맞춘다)
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// 메뉴 막대 창의 모서리를 둥글게 깎는다. MenuBarExtra 는 창 모양을 정하는 옵션이 없어 NSWindow 를 직접 만진다.
struct RoundedWindow: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(v.window) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { apply(v.window) }
    }

    private func apply(_ w: NSWindow?) {
        guard let w else { return }
        w.isOpaque = false
        w.backgroundColor = .clear
        for view in [w.contentView, w.contentView?.superview].compactMap({ $0 }) {
            view.wantsLayer = true
            view.layer?.cornerRadius = radius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
        w.invalidateShadow()
    }
}
