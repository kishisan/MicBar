import AVFoundation
import CoreAudio
import Foundation

struct MicState: Equatable {
    let isActive: Bool
    let isMuted: Bool
    let deviceName: String?
    let activeSince: Date?
}

final class AudioDeviceMonitor {
    var onStateChanged: ((MicState) -> Void)?

    private enum DetectionSource {
        case coreAudioHAL
        case avCaptureDevice
        case dictationProcess
    }

    private var currentState = MicState(isActive: false, isMuted: false, deviceName: nil, activeSince: nil)
    private var activationSource: DetectionSource?
    private var pollingTimer: Timer?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var runningListenerBlocks: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []
    private var muteListenerBlocks: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []

    private let normalPollingInterval: TimeInterval = 1.0
    private let fastPollingInterval: TimeInterval = 0.3

    init() {}

    func start() {
        registerDeviceListListener()
        registerDefaultInputDeviceListener()
        updateDevices()
        startPolling()

        // Instant dictation detection via input source notification
        DictationDetector.onStateChanged = { [weak self] in
            self?.pollState()
        }
        DictationDetector.startMonitoring()
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        activationSource = nil
        DictationDetector.stopMonitoring()
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

    // MARK: - Default Input Device Listener

    private func registerDefaultInputDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                #if DEBUG
                NSLog("[MicBar] Default input device changed")
                #endif
                self?.updateDevices()
            }
        }
        defaultInputDeviceListenerBlock = block

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

    // MARK: - Device Mute State

    private func isDeviceMuted(_ deviceID: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var isMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isMuted)
        guard status == noErr else { return nil }
        return isMuted != 0
    }

    // MARK: - Default Input Device

    private func getDefaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
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
                    #if DEBUG
                    NSLog("[MicBar] Running state changed for device %u", deviceID)
                    #endif
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

    // MARK: - Per-Device Mute Listeners

    private func registerMuteListeners(for deviceIDs: [AudioObjectID]) {
        removeMuteListeners()

        for deviceID in deviceIDs {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    #if DEBUG
                    NSLog("[MicBar] Mute state changed for device %u", deviceID)
                    #endif
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
                muteListenerBlocks.append((deviceID, block))
            }
        }
    }

    private func removeMuteListeners() {
        for (deviceID, block) in muteListenerBlocks {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        muteListenerBlocks.removeAll()
    }

    // MARK: - Cleanup

    private func removeAllListeners() {
        removeRunningListeners()
        removeMuteListeners()

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

        if let block = defaultInputDeviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            defaultInputDeviceListenerBlock = nil
        }
    }

    // MARK: - AVCaptureDevice Fallback

    private func isAnyMicInUseViaAVCapture() -> (inUse: Bool, deviceName: String?) {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInMicrophone]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.external)
        } else {
            deviceTypes.append(.externalUnknown)
        }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )

        for device in session.devices {
            if device.isInUseByAnotherApplication {
                #if DEBUG
                NSLog("[MicBar] AVCapture fallback: %@ is in use by another app", device.localizedName)
                #endif
                return (true, device.localizedName)
            }
        }
        return (false, nil)
    }

    // MARK: - Update Logic

    private func updateDevices() {
        let inputDevices = getInputDeviceIDs()
        registerRunningListeners(for: inputDevices)
        registerMuteListeners(for: inputDevices)
        pollState()
    }

    func pollState() {
        let inputDevices = getInputDeviceIDs()

        // Check all three detection layers every poll cycle
        var halActive = false
        var halDeviceName: String?

        #if DEBUG
        NSLog("[MicBar] pollState: found %d input device(s)", inputDevices.count)
        #endif

        for deviceID in inputDevices {
            let running = isDeviceRunning(deviceID)
            let muted = isDeviceMuted(deviceID)
            let name = deviceName(deviceID)

            #if DEBUG
            NSLog("[MicBar]   device %u (%@): running=%d, muted=%@",
                  deviceID,
                  name ?? "unknown",
                  running ? 1 : 0,
                  muted.map { $0 ? "true" : "false" } ?? "N/A")
            #endif

            if running {
                halActive = true
                halDeviceName = name
                break
            }
        }

        let avResult = isAnyMicInUseViaAVCapture()
        let dictationActive = DictationDetector.isActive()

        #if DEBUG
        NSLog("[MicBar] Detection layers: HAL=%d, AVCapture=%d, Dictation=%d, activationSource=%@",
              halActive ? 1 : 0,
              avResult.inUse ? 1 : 0,
              dictationActive ? 1 : 0,
              activationSource.map { "\($0)" } ?? "nil")
        #endif

        // Determine active state using source-tracking logic.
        // DictationDetector uses CPU time tracking, so it correctly returns false
        // for lingering DictationIM processes (0% CPU).
        var anyActive = false
        var activeDeviceName: String?

        if halActive {
            // CoreAudio HAL has highest priority — always trust it
            anyActive = true
            activeDeviceName = halDeviceName
            activationSource = .coreAudioHAL
        } else if avResult.inUse {
            // AVCapture confirms mic is in use — trust it
            anyActive = true
            activeDeviceName = avResult.deviceName
            activationSource = .avCaptureDevice
        } else if currentState.isActive, let source = activationSource {
            // Already active: only the original detection source can declare "stopped"
            switch source {
            case .coreAudioHAL:
                // HAL stopped → inactive
                anyActive = false
            case .avCaptureDevice:
                // AVCapture stopped → inactive
                anyActive = false
            case .dictationProcess:
                // Trust DictationDetector (CPU-based, no false positives from lingering)
                anyActive = dictationActive
                activeDeviceName = "Dictation"
            }
            if !anyActive {
                activationSource = nil
            }
        } else {
            // Not currently active: any layer can trigger activation
            if dictationActive {
                anyActive = true
                activeDeviceName = "Dictation"
                activationSource = .dictationProcess
            }
        }

        // Check mute state of default input device
        let isMuted: Bool
        if let defaultDeviceID = getDefaultInputDeviceID() {
            isMuted = isDeviceMuted(defaultDeviceID) ?? false
        } else {
            isMuted = false
        }

        let activeSince: Date?
        if anyActive {
            activeSince = currentState.isActive ? currentState.activeSince : Date()
        } else {
            activeSince = nil
        }

        let newState = MicState(
            isActive: anyActive,
            isMuted: isMuted,
            deviceName: activeDeviceName,
            activeSince: activeSince
        )

        if newState != currentState {
            #if DEBUG
            NSLog("[MicBar] State changed: active=%d, muted=%d, device=%@, source=%@",
                  newState.isActive ? 1 : 0,
                  newState.isMuted ? 1 : 0,
                  newState.deviceName ?? "none",
                  activationSource.map { "\($0)" } ?? "nil")
            #endif
            currentState = newState
            onStateChanged?(newState)
        }

        // Adaptive polling: poll faster when dictation is active or DictationIM is
        // present (ready to detect start/stop quickly), normal speed otherwise
        let needsFastPolling = anyActive || DictationDetector.isDictating || dictationActive
        adjustPollingSpeed(fast: needsFastPolling)
    }

    // MARK: - Polling

    private func startPolling() {
        scheduleTimer(interval: normalPollingInterval)
    }

    private var currentPollingInterval: TimeInterval = 0

    private func adjustPollingSpeed(fast: Bool) {
        let desired = fast ? fastPollingInterval : normalPollingInterval
        if desired != currentPollingInterval {
            scheduleTimer(interval: desired)
            #if DEBUG
            NSLog("[MicBar] Polling interval: %.1fs", desired)
            #endif
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        pollingTimer?.invalidate()
        currentPollingInterval = interval
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.pollState()
        }
    }
}
