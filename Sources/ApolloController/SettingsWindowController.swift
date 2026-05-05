import AppKit

final class SettingsWindowController: NSWindowController {
    var onSave: ((ShortcutConfig) -> Void)?

    private var config: ShortcutConfig
    private var recorders: [KeyRecorderField] = []

    init(config: ShortcutConfig) {
        self.config = config
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Apollo Controller — Shortcuts"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func open() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        let rows: [(String, KeyPath<ShortcutConfig, KeyBinding>)] = [
            ("Volume Up",   \.volumeUp),
            ("Volume Down", \.volumeDown),
            ("Mute Toggle", \.mute),
            ("Dim Toggle",  \.dim),
        ]

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 10
        outer.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        outer.translatesAutoresizingMaskIntoConstraints = false

        recorders = []
        for (label, kp) in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10

            let lbl = NSTextField(labelWithString: label + ":")
            lbl.alignment = .right
            lbl.widthAnchor.constraint(equalToConstant: 110).isActive = true

            let rec = KeyRecorderField(binding: config[keyPath: kp])
            rec.widthAnchor.constraint(equalToConstant: 160).isActive = true
            rec.onChanged = { [weak self] _ in self?.syncConfig() }

            recorders.append(rec)
            row.addArrangedSubview(lbl)
            row.addArrangedSubview(rec)
            outer.addArrangedSubview(row)
        }

        // Flex spacer to push buttons to the bottom
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        outer.addArrangedSubview(spacer)

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal

        let reset  = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        let btnSpacer = NSView()
        btnSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let save   = NSButton(title: "Save", target: self, action: #selector(saveConfig))
        save.keyEquivalent = "\r"

        btnRow.addArrangedSubview(reset)
        btnRow.addArrangedSubview(btnSpacer)
        btnRow.addArrangedSubview(save)
        outer.addArrangedSubview(btnRow)

        guard let contentView = window?.contentView else { return }
        contentView.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func syncConfig() {
        config.volumeUp   = recorders[0].binding
        config.volumeDown = recorders[1].binding
        config.mute       = recorders[2].binding
        config.dim        = recorders[3].binding
    }

    @objc private func resetDefaults() {
        config = .default
        zip(recorders, [config.volumeUp, config.volumeDown, config.mute, config.dim])
            .forEach { $0.updateBinding($1) }
    }

    @objc private func saveConfig() {
        syncConfig()
        config.save()
        onSave?(config)
        window?.close()
    }
}
