import Carbon
import Foundation

private enum HotkeyID: UInt32 {
    case volumeUp   = 1
    case volumeDown = 2
    case mute       = 3
    case dim        = 4
}

var _onVolumeUp:   (() -> Void)?
var _onVolumeDown: (() -> Void)?
var _onMute:       (() -> Void)?
var _onDim:        (() -> Void)?

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hkID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    switch HotkeyID(rawValue: hkID.id) {
    case .volumeUp:   _onVolumeUp?()
    case .volumeDown: _onVolumeDown?()
    case .mute:       _onMute?()
    case .dim:        _onDim?()
    case .none:       break
    }
    return noErr
}

class HotkeyManager {
    private var refs: [EventHotKeyRef?] = [nil, nil, nil, nil]
    private var handlerRef: EventHandlerRef?
    private let sig = OSType(0x4150_4354)  // 'APCT'

    func register(
        config:       ShortcutConfig,
        onVolumeUp:   @escaping () -> Void,
        onVolumeDown: @escaping () -> Void,
        onMute:       @escaping () -> Void,
        onDim:        @escaping () -> Void
    ) {
        _onVolumeUp   = onVolumeUp
        _onVolumeDown = onVolumeDown
        _onMute       = onMute
        _onDim        = onDim

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        bindKeys(config: config)
        writeLog("Hotkeys: \(config.volumeUp.displayString)=Up  \(config.volumeDown.displayString)=Down  \(config.mute.displayString)=Mute  \(config.dim.displayString)=Dim")
    }

    func reconfigure(config: ShortcutConfig) {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        refs = [nil, nil, nil, nil]
        bindKeys(config: config)
        writeLog("Hotkeys reconfigured: \(config.volumeUp.displayString)=Up  \(config.volumeDown.displayString)=Down  \(config.mute.displayString)=Mute  \(config.dim.displayString)=Dim")
    }

    private func bindKeys(config: ShortcutConfig) {
        let bindings: [(HotkeyID, KeyBinding)] = [
            (.volumeUp,   config.volumeUp),
            (.volumeDown, config.volumeDown),
            (.mute,       config.mute),
            (.dim,        config.dim),
        ]
        for (i, (id, binding)) in bindings.enumerated() {
            let hkID = EventHotKeyID(signature: sig, id: id.rawValue)
            RegisterEventHotKey(binding.keyCode, binding.modifiers, hkID,
                                GetApplicationEventTarget(), 0, &refs[i])
        }
    }

    func unregister() {
        refs.compactMap { $0 }.forEach { UnregisterEventHotKey($0) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
