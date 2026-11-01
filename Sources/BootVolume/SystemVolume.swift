import AudioToolbox
import CoreAudio

/// 기본 출력 장치의 음량(0~100)과 음소거를 CoreAudio 로 직접 읽고 쓴다.
enum SystemVolume {
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return st == noErr && id != 0 ? id : nil
    }

    private static var volumeAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// 0~100. 음소거 중이면 0.
    static func get() -> Int? {
        guard let dev = defaultOutputDevice() else { return nil }
        if isMuted(dev) { return 0 }
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &volumeAddr, 0, nil, &size, &v) == noErr else { return nil }
        return Int((v * 100).rounded())
    }

    /// 0 이면 음소거까지, 그 외에는 음소거를 풀고 음량을 맞춘다.
    @discardableResult
    static func set(_ percent: Int) -> Bool {
        guard let dev = defaultOutputDevice() else { return false }
        let p = min(max(percent, 0), 100)
        var v = Float32(p) / 100
        let size = UInt32(MemoryLayout<Float32>.size)
        let ok = AudioObjectSetPropertyData(dev, &volumeAddr, 0, nil, size, &v) == noErr
        setMuted(dev, p == 0)
        return ok
    }

    /// 음량(0~1)과 음소거를 그대로 기억해 두었다가 되돌릴 때 쓴다.
    struct State {
        let level: Float32
        let muted: Bool
    }

    static func snapshot() -> State? {
        guard let dev = defaultOutputDevice() else { return nil }
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &volumeAddr, 0, nil, &size, &v) == noErr else { return nil }
        return State(level: v, muted: isMuted(dev))
    }

    /// 음량을 먼저 되돌리고 음소거를 맞춘다(음소거를 먼저 풀면 잠깐 큰 소리가 날 수 있다).
    static func restore(_ s: State) {
        guard let dev = defaultOutputDevice() else { return }
        var v = s.level
        AudioObjectSetPropertyData(dev, &volumeAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        setMuted(dev, s.muted)
    }

    /// 음소거는 건드리지 않고 음량(0~100)만 바꾼다.
    static func setLevel(_ percent: Int) {
        guard let dev = defaultOutputDevice() else { return }
        var v = Float32(min(max(percent, 0), 100)) / 100
        AudioObjectSetPropertyData(dev, &volumeAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    static func setMuted(_ muted: Bool) {
        guard let dev = defaultOutputDevice() else { return }
        setMuted(dev, muted)
    }

    private static func isMuted(_ dev: AudioDeviceID) -> Bool {
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &size, &m) == noErr else { return false }
        return m != 0
    }

    private static func setMuted(_ dev: AudioDeviceID, _ muted: Bool) {
        var m = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(dev, &muteAddr, 0, nil, size, &m)
    }
}
