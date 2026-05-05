import AppKit
import Carbon

// A button that enters "recording" mode on click and captures the next key combo.
// Click again or press Escape to cancel.
final class KeyRecorderField: NSButton {
    private(set) var binding: KeyBinding
    var onChanged: ((KeyBinding) -> Void)?

    private var isRecording = false
    private var monitor: Any?

    init(binding: KeyBinding) {
        self.binding = binding
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = binding.displayString
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateBinding(_ b: KeyBinding) {
        binding = b
        if !isRecording { title = b.displayString }
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording(save: false) : startRecording()
    }

    private func startRecording() {
        isRecording = true
        title = "Press shortcut…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording(save: false)
            return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.isEmpty else { return }
        binding = .make(keyCode: UInt32(event.keyCode), carbonModifiers: nsModsToCarbonMods(mods))
        onChanged?(binding)
        stopRecording(save: true)
    }

    private func stopRecording(save: Bool) {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        title = binding.displayString
    }
}

private func nsModsToCarbonMods(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var c: UInt32 = 0
    if flags.contains(.command) { c |= UInt32(cmdKey) }
    if flags.contains(.shift)   { c |= UInt32(shiftKey) }
    if flags.contains(.option)  { c |= UInt32(optionKey) }
    if flags.contains(.control) { c |= UInt32(controlKey) }
    return c
}
