import AppKit

// Must be a global — NSApp.delegate is weak, so a local var would be released
// during the run loop causing a crash (EXC_BAD_ACCESS in objc_release).
let _appDelegate = AppDelegate()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = _appDelegate
app.run()
