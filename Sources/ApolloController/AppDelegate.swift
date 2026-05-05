import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let ua     = UAClient(outputIndex: 4)
    private let hotkey = HotkeyManager()
    private var config = ShortcutConfig.load()
    private var settingsWC: SettingsWindowController?

    private let stepPercent = 0.05

    // Icons
    private var iconNormal:       NSImage?
    private var iconMuted:        NSImage?
    private var iconDisconnected: NSImage?

    // Menu items
    private var menuItemUp:       NSMenuItem!
    private var menuItemDown:     NSMenuItem!
    private var menuItemMute:     NSMenuItem!
    private var menuItemDim:      NSMenuItem!
    private var sliderMenuItem:   NSMenuItem!
    private var disconnectedItem: NSMenuItem!
    private var volumeSlider:     NSSlider!
    private var volumeLabel:      NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadIcons()
        setupStatusItem()
        setupHotkeys()

        ua.onStateChanged = { [weak self] in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        ua.connect()
        updateStatus()
        writeLog("[Apollo Controller] Running — using direct UA Mixer Engine TCP control on :4710")
    }

    // MARK: - Icons

    private func loadIcons() {
        iconNormal       = loadIcon("ua-commander")
        iconMuted        = loadIcon("ua-commander-red-stripe")
        iconDisconnected = loadIcon("ua-commander-yellow-mark")
    }

    private func loadIcon(_ name: String) -> NSImage? {
        guard let img = Bundle.module.image(forResource: name) else { return nil }
        img.isTemplate = false
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Apollo Twin Volume Controller", action: nil, keyEquivalent: ""))

        sliderMenuItem = NSMenuItem()
        sliderMenuItem.view = makeSliderView()
        menu.addItem(sliderMenuItem)

        disconnectedItem = NSMenuItem(title: "Not connected to Mixer Engine", action: nil, keyEquivalent: "")
        disconnectedItem.isEnabled = false
        menu.addItem(disconnectedItem)

        menu.addItem(.separator())

        menuItemUp   = item("", action: #selector(volumeUp))
        menuItemDown = item("", action: #selector(volumeDown))
        menuItemMute = item("", action: #selector(toggleMute))
        menuItemDim  = item("", action: #selector(toggleDim))

        menu.addItem(menuItemUp)
        menu.addItem(menuItemDown)
        menu.addItem(menuItemMute)
        menu.addItem(menuItemDim)
        menu.addItem(.separator())
        menu.addItem(item("Shortcuts…",    action: #selector(openSettings)))
        menu.addItem(item("Open Log File", action: #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(quit)))

        statusItem.menu = menu
        updateMenuTitles()
    }

    private func makeSliderView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 30))

        volumeSlider = NSSlider(frame: NSRect(x: 14, y: 5, width: 192, height: 20))
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.isContinuous = true
        volumeSlider.target = self
        volumeSlider.action = #selector(sliderMoved)

        volumeLabel = NSTextField(labelWithString: "0%")
        volumeLabel.frame = NSRect(x: 210, y: 8, width: 38, height: 14)
        volumeLabel.alignment = .right
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        container.addSubview(volumeSlider)
        container.addSubview(volumeLabel)
        return container
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func updateMenuTitles() {
        menuItemUp.title   = "Volume Up    \(config.volumeUp.displayString)"
        menuItemDown.title = "Volume Down  \(config.volumeDown.displayString)"
        menuItemMute.title = "Mute Toggle  \(config.mute.displayString)"
        menuItemDim.title  = "Dim Toggle   \(config.dim.displayString)"
    }

    private func updateStatus() {
        let pct = Int((ua.monitorLevel * 100).rounded())

        // Toolbar icon
        if !ua.isConnected {
            statusItem.button?.image = iconDisconnected
        } else if ua.isMuted || pct == 0 {
            statusItem.button?.image = iconMuted
        } else {
            statusItem.button?.image = iconNormal
        }
        statusItem.button?.title = ""

        // Slider vs. disconnected message
        sliderMenuItem.isHidden   = !ua.isConnected
        disconnectedItem.isHidden = ua.isConnected

        // Sync slider + label to current level
        if ua.isConnected {
            volumeSlider.doubleValue = ua.monitorLevel
            volumeLabel.stringValue  = "\(pct)%"
        }
    }

    // MARK: - Actions

    @objc private func sliderMoved() {
        ua.setLevel(volumeSlider.doubleValue)
    }

    @objc private func volumeUp()   { ua.adjustLevel(by:  stepPercent) }
    @objc private func volumeDown() { ua.adjustLevel(by: -stepPercent) }
    @objc private func toggleMute() { ua.toggleMute() }
    @objc private func toggleDim()  { ua.toggleDim() }

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(config: config)
            settingsWC?.onSave = { [weak self] newConfig in
                guard let self else { return }
                self.config = newConfig
                self.hotkey.reconfigure(config: newConfig)
                self.updateMenuTitles()
            }
        }
        settingsWC?.open()
    }

    @objc private func openLog() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/ApolloController.log")
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func quit() {
        hotkey.unregister()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkey.register(
            config:       config,
            onVolumeUp:   { [weak self] in self?.volumeUp() },
            onVolumeDown: { [weak self] in self?.volumeDown() },
            onMute:       { [weak self] in self?.toggleMute() },
            onDim:        { [weak self] in self?.toggleDim() }
        )
    }
}
