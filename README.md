<div align="center">
  <img src="assets/ua-commander-hi-res.png" width="120" alt="UA Commander">
  <h1>UA Commander</h1>
  <p>Keyboard control for Universal Audio Apollo Twin X — no MIDI, no setup, no clicks.</p>

  ![macOS](https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square&color=0066B8)
  ![Swift](https://img.shields.io/badge/Swift-5.9-blue?style=flat-square&color=2EA3FF)
  ![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square&color=003A6B)
</div>

---

UA Commander lives in your menu bar and connects directly to the UA Mixer Engine running on your Mac. Adjust monitor level, mute, and dim from any application — while recording, while mixing, without touching the mouse.

It speaks the Mixer Engine's internal IPC protocol over TCP on `127.0.0.1:4710`. No MIDI Learn. No drivers. No extra permissions.

---

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel
- A UA Apollo Twin X with **UAD Console** running (the Mixer Engine must be active)
- Xcode Command Line Tools — install with `xcode-select --install`

---

## Install

### Option A — Download (no Xcode required)

1. Go to [**Releases**](https://github.com/kalskiid/ApolloController/releases/latest)
2. Download the zip for your Mac — `arm64` for Apple Silicon (M1 and later), `x86_64` for Intel
3. Unzip and run:

```bash
./install.sh
```

### Option B — Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/kalskiid/ApolloController.git
cd ApolloController
./install.sh
```

The installer registers a LaunchAgent so the app starts at login and launches it immediately. The menu bar icon appears within a few seconds.

---

## Menu bar icon

| Icon | State |
|---|---|
| Normal logo | Connected, volume audible |
| Red-stripe logo | Muted or volume at 0% |
| Yellow-mark logo | Not connected to Mixer Engine |

The icon stays in sync with UAD Console and the physical knob in real time. Open the menu to see a live volume slider.

---

## Default keyboard shortcuts

| Action | Shortcut |
|---|---|
| Volume +5% | <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>↑</kbd> |
| Volume −5% | <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>↓</kbd> |
| Mute toggle | <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>M</kbd> |
| Dim toggle | <kbd>⌘</kbd> <kbd>⌥</kbd> <kbd>D</kbd> |

All four shortcuts are configurable. Open the menu → **Shortcuts…**, click any action, press your preferred key combo, hit Save. Settings persist across restarts.

---

## How it works

UA Commander reverse-engineers the UA Mixer Engine's local IPC protocol. Commands are null-terminated strings sent over TCP:

```
set /devices/0/outputs/4/CRMonitorLevelTapered/value?context_type=main&func_id=1001 0.75\0
```

Responses are null-terminated JSON. The app also subscribes to state changes, so turning the physical knob or adjusting level in UAD Console is immediately reflected in the menu bar icon and slider.

Key paths used:

| Path | Type | Notes |
|---|---|---|
| `CRMonitorLevelTapered/value` | float 0–1 | Tapered monitor level |
| `Mute/value` | bool | Monitor mute |
| `DimOn/value` | bool | Dim active |

---

## Logs

```
~/Library/Logs/ApolloController.log
```

Or open it directly from the menu → **Open Log File**.

---

## Uninstall

```bash
./uninstall.sh
```

Stops the process, removes the LaunchAgent, leaves nothing else behind.

---

## License

MIT — see [LICENSE](LICENSE).  
© 2026 Rosen Stoyanov.
