import CoreAudio
import Foundation

struct MicState: Equatable {
    let isActive: Bool
    let deviceName: String?
    let activeSince: Date?
}

final class AudioDeviceMonitor {
    var onStateChanged: ((MicState) -> Void)?

    private var currentState = MicState(isActive: false, deviceName: nil, activeSince: nil)
    private var pollingTimer: Timer?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var runningListenerBlocks: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []

    private let pollingInterval: TimeInterval = 3.0

    init() {}

    func start() {
        registerDeviceListListener()
        updateDevices()
        startPolling()
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        removeAllListeners()
    }

    // MARK: - Device List Listener

    private func registerDeviceListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateDevices()
            }
        }
        deviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Enumerate Input Devices

    private func getInputDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.filter { hasInputStreams($0) }
    }

    private func hasInputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    // MARK: - Device Running State

    private func isDeviceRunning(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isRunning)
        return status == noErr && isRunning != 0
    }

    private func deviceName(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr, let cfName = name?.takeUnretainedValue() else { return nil }
        return cfName as String
    }

    // MARK: - Per-Device Running Listeners

    private func registerRunningListeners(for deviceIDs: [AudioObjectID]) {
        removeRunningListeners()

        for deviceID in deviceIDs {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.pollState()
                }
            }

            let status = AudioObjectAddPropertyListenerBlock(
                deviceID,
                &address,
                DispatchQueue.main,
                block
            )

            if status == noErr {
                runningListenerBlocks.append((deviceID, block))
            }
        }
    }

    private func removeRunningListeners() {
        for (deviceID, block) in runningListenerBlocks {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        runningListenerBlocks.removeAll()
    }

    private func removeAllListeners() {
        removeRunningListeners()

        if let block = deviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            deviceListenerBlock = nil
        }
    }

    // MARK: - Update Logic

    private func updateDevices() {
        let inputDevices = getInputDeviceIDs()
        registerRunningListeners(for: inputDevices)
        pollState()
    }

    func pollState() {
        let inputDevices = getInputDeviceIDs()

        var activeDeviceName: String?
        var anyActive = false

        for deviceID in inputDevices {
            if isDeviceRunning(deviceID) {
                anyActive = true
                activeDeviceName = deviceName(deviceID)
                break
            }
        }

        let activeSince: Date?
        if anyActive {
            activeSince = currentState.isActive ? currentState.activeSince : Date()
        } else {
            activeSince = nil
        }

        let newState = MicState(
            isActive: anyActive,
            deviceName: activeDeviceName,
            activeSince: activeSince
        )

        if newState != currentState {
            currentState = newState
            onStateChanged?(newState)
        }
    }

    // MARK: - Polling Fallback

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) {
            [weak self] _ in
            self?.pollState()
        }
    }
}
