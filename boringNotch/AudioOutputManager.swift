import Combine
import CoreAudio
import Foundation

@MainActor
final class AudioOutputManager: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String

        var symbol: String {
            let lower = name.lowercased()
            if lower.contains("airpods") { return "airpodspro" }
            if lower.contains("headphone") || lower.contains("buds") { return "headphones" }
            if lower.contains("display") || lower.contains("monitor") { return "display" }
            return "speaker.wave.2.fill"
        }
    }

    static let shared = AudioOutputManager()

    @Published private(set) var devices: [Device] = []
    @Published private(set) var selectedID: AudioDeviceID?
    @Published var message: String?

    private var refreshTimer: AnyCancellable?

    private init() {
        refresh()
        refreshTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    var selectedDevice: Device? { devices.first { $0.id == selectedID } }

    func select(_ device: Device) {
        guard device.id != selectedID else { return }
        var chosenID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &chosenID
        )
        if status == noErr {
            message = nil
            refresh()
        } else {
            message = "Could not switch audio output."
        }
    }

    func refresh() {
        let found = Self.outputDevices()
        let active = Self.defaultOutputDevice()
        if found != devices { devices = found }
        if active != selectedID { selectedID = active }
    }

    private static func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.filter(hasOutput).map { Device(id: $0, name: name(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let name else { return "Audio device" }
        return name as String
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != 0 else { return nil }
        return id
    }
}
