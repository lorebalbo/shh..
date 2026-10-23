import AudioToolbox
import CoreAudio
import Foundation

/// The default output device's mute switch and volume, as used by SystemAudioMuter.
/// Abstracted so the mute/restore logic can be tested without touching the Mac's sound.
protocol SystemAudioOutput: AnyObject {
    /// The current default output device, or nil if there is none.
    var defaultDevice: AudioObjectID? { get }
    /// Whether the device is muted, or nil if it has no mute switch we can change.
    func isMuted(_ device: AudioObjectID) -> Bool?
    @discardableResult func setMuted(_ muted: Bool, on device: AudioObjectID) -> Bool
    /// The device's volume (0–1), or nil if it has no volume we can change.
    func volume(_ device: AudioObjectID) -> Float32?
    @discardableResult func setVolume(_ volume: Float32, on device: AudioObjectID) -> Bool
}

/// Silences the Mac's sound while a recording is in progress so nothing it plays
/// bleeds into the microphone, then puts the output back exactly as it was.
///
/// Uses the default output device's mute switch, or turns its volume to zero on
/// devices without one (some HDMI and USB outputs). Output the user had already
/// silenced is left alone, so restoring never unmutes something we didn't mute.
final class SystemAudioMuter {
    private enum Silenced {
        case muted(AudioObjectID)
        case volume(AudioObjectID, previous: Float32)
    }

    private let output: SystemAudioOutput
    private var silenced: Silenced?

    init(output: SystemAudioOutput = CoreAudioOutput()) {
        self.output = output
    }

    /// True while the output is silenced by us and waiting for `restore()`.
    var isSilencing: Bool { silenced != nil }

    /// Silences the default output device. Does nothing if it is already silenced.
    func mute() {
        guard silenced == nil, let device = output.defaultDevice else { return }

        if let isMuted = output.isMuted(device) {
            if isMuted { return }
            if output.setMuted(true, on: device) {
                silenced = .muted(device)
                return
            }
        }

        if let volume = output.volume(device), volume > 0, output.setVolume(0, on: device) {
            silenced = .volume(device, previous: volume)
        }
    }

    /// Puts back the mute switch or volume changed by `mute()`, on the same device
    /// even if the default output changed in the meantime.
    func restore() {
        guard let silenced else { return }
        self.silenced = nil
        switch silenced {
        case .muted(let device):
            output.setMuted(false, on: device)
        case .volume(let device, let previous):
            output.setVolume(previous, on: device)
        }
    }
}

/// SystemAudioOutput backed by the Core Audio HAL.
final class CoreAudioOutput: SystemAudioOutput {
    var defaultDevice: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    func isMuted(_ device: AudioObjectID) -> Bool? {
        settableValue(kAudioDevicePropertyMute, of: device, initial: UInt32(0)).map { $0 != 0 }
    }

    func setMuted(_ muted: Bool, on device: AudioObjectID) -> Bool {
        setValue(UInt32(muted ? 1 : 0), for: kAudioDevicePropertyMute, on: device)
    }

    func volume(_ device: AudioObjectID) -> Float32? {
        settableValue(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, of: device, initial: Float32(0))
    }

    func setVolume(_ volume: Float32, on device: AudioObjectID) -> Bool {
        setValue(volume, for: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, on: device)
    }

    // MARK: - Private

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Reads an output property, or returns nil when the device doesn't have it or won't let us change it.
    private func settableValue<Value>(
        _ selector: AudioObjectPropertySelector,
        of device: AudioObjectID,
        initial: Value
    ) -> Value? {
        var address = Self.outputAddress(selector)
        var isSettable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return nil }

        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func setValue<Value>(_ value: Value, for selector: AudioObjectPropertySelector, on device: AudioObjectID) -> Bool {
        var address = Self.outputAddress(selector)
        var value = value
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value
        ) == noErr
    }
}
