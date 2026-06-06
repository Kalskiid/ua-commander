import Foundation
import Network

// Direct client for the UA Mixer Engine IPC protocol on localhost:4710.
// Protocol (reverse-engineered from packet capture):
//   client -> server: "<verb> <path>?<query> <value>\0"   (null-terminated text)
//   server -> client: '{"path":"...","parameters":{...},"data":...}\0' (JSON, null-terminated)
//   verbs observed: get, set, sub (subscribe), unsub
//
// Device and output indices are NOT hardcoded — they are discovered at connect
// time (see startDiscovery). The monitor output sits at different indices across
// Apollo models, so it is identified by role: the output whose IOType == "Monitor"
// and that carries a CRMonitorLevelTapered property. This is verified on the
// Apollo Twin X (output 4) and expected to generalize across the Apollo range,
// but has not yet been confirmed on non-Twin hardware (x6/x8/x16/etc.).
final class UAClient {
    private let host = NWEndpoint.Host("127.0.0.1")
    private let port: NWEndpoint.Port = 4710

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.kalskiid.ua-commander.ua")
    private var funcId: Int = 1000
    private var rxBuffer = Data()
    private var heartbeat: DispatchSourceTimer?

    // Incremented on every reconnect so callbacks from old connections are ignored.
    private var generation: Int = 0

    // Current cached state
    private(set) var monitorLevel: Double = 0.5  // tapered 0..1
    private(set) var isMuted: Bool = false
    private(set) var isDim: Bool = false
    private(set) var isConnected: Bool = false
    // True only when the Apollo hardware is physically present, reported by the
    // engine's DeviceOnline property — distinct from TCP connectivity: the Mixer
    // Engine keeps the socket open even when the device is unplugged.
    private(set) var isDevicePresent: Bool = false

    var onStateChanged: (() -> Void)?

    // Discovered at connect time. deviceId defaults to the first device found;
    // outputIndex stays nil until the monitor output is located, and normal
    // operation (subscriptions + heartbeat) only begins once it is set.
    private var deviceId: Int = 0
    private var outputIndex: Int?

    // Discovery scratch: output ids still to probe, and the monitor-role outputs found.
    private var pendingOutputs: [Int] = []
    private var monitorOutputs: [Int] = []

    init() {}

    // MARK: - Connection lifecycle

    func connect() {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        connection = conn
        let gen = generation
        conn.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == gen else { return }
            switch state {
            case .ready:
                writeLog("[UA] Connected to UA Mixer Engine on \(self.host):\(self.port)")
                self.isConnected = true
                self.onStateChanged?()
                self.startReceive(gen: gen)
                self.startDiscovery()
            case .failed(let err):
                writeLog("[UA] Connection failed: \(err) — retrying in 3s")
                self.isConnected = false
                self.isDevicePresent = false
                self.stopHeartbeat()
                self.onStateChanged?()
                self.queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.reconnect() }
            case .cancelled:
                writeLog("[UA] Connection cancelled")
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func reconnect() {
        generation += 1
        connection?.cancel()
        connection = nil
        rxBuffer.removeAll()
        // Re-discover from scratch — the device set may have changed.
        outputIndex = nil
        pendingOutputs.removeAll()
        monitorOutputs.removeAll()
        connect()
    }

    private func startReceive(gen: Int) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, self.generation == gen else { return }
            if let data = data, !data.isEmpty {
                self.rxBuffer.append(data)
                self.parseFrames()
            }
            if let error = error {
                writeLog("[UA] Receive error: \(error)")
                return
            }
            if isComplete {
                writeLog("[UA] Connection complete — will reconnect")
                self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reconnect() }
                return
            }
            self.startReceive(gen: gen)
        }
    }

    // Frames are null-terminated JSON objects.
    private func parseFrames() {
        while let nullIdx = rxBuffer.firstIndex(of: 0) {
            let frame = rxBuffer[..<nullIdx]
            rxBuffer.removeSubrange(...nullIdx)
            guard let text = String(data: frame, encoding: .utf8), !text.isEmpty else { continue }
            handleMessage(text)
        }
    }

    private func handleMessage(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let path = obj["path"] as? String

        // Until the monitor output is known, every response is discovery traffic.
        guard let outputIndex else {
            handleDiscoveryMessage(path: path, obj: obj)
            return
        }

        if let err = obj["error"] as? String {
            writeLog("[UA] Server error: \(err) on \(path ?? "?")")
            return
        }

        guard let path else { return }
        let value = obj["data"]

        switch path {
        case "/devices/\(deviceId)/outputs/\(outputIndex)/CRMonitorLevelTapered/value":
            if let d = value as? Double { monitorLevel = d; onStateChanged?() }
        case "/devices/\(deviceId)/outputs/\(outputIndex)/Mute/value":
            if let b = value as? Bool { isMuted = b; onStateChanged?() }
        case "/devices/\(deviceId)/outputs/\(outputIndex)/DimOn/value":
            if let b = value as? Bool { isDim = b; onStateChanged?() }
        case "/devices/\(deviceId)/DeviceOnline/value":
            // Pushed shape (if the engine ever supports it); we currently poll.
            if let b = value as? Bool { setDevicePresent(b) }
        case "/devices/\(deviceId)/DeviceOnline":
            // Polled GET response: {"data":{"type":"bool","value":<bool>}}.
            if let dict = value as? [String: Any] {
                if let b = dict["value"] as? Bool {
                    setDevicePresent(b)
                } else if let b = ((dict["properties"] as? [String: Any])?["value"] as? [String: Any])?["value"] as? Bool {
                    setDevicePresent(b)
                }
            } else if let b = value as? Bool {
                setDevicePresent(b)
            }
        case "/devices/\(deviceId)/outputs/\(outputIndex)":
            // Full state object (response to initial GET and heartbeat pings)
            if let outer = value as? [String: Any],
               let props = outer["properties"] as? [String: Any] {
                if let lvl = (props["CRMonitorLevelTapered"] as? [String: Any])?["value"] as? Double {
                    monitorLevel = lvl
                }
                if let m = (props["Mute"] as? [String: Any])?["value"] as? Bool {
                    isMuted = m
                }
                if let d = (props["DimOn"] as? [String: Any])?["value"] as? Bool {
                    isDim = d
                }
                onStateChanged?()
            }
        default:
            break
        }
    }

    private func setDevicePresent(_ present: Bool) {
        guard isDevicePresent != present else { return }
        isDevicePresent = present
        writeLog("[UA] Apollo \(present ? "online" : "offline")")
        onStateChanged?()
    }

    // MARK: - Discovery
    //
    // Walks the device tree to locate the controllable monitor output without
    // hardcoding indices:
    //   1. get /devices                  -> device ids (pick the first)
    //   2. get /devices/{id}/outputs     -> output ids
    //   3. get /devices/{id}/outputs/{n} -> first with IOType == "Monitor"
    //                                       carrying CRMonitorLevelTapered
    // If anything is missing (no device / no monitor / device unplugged at launch)
    // discovery retries on a timer, so plugging in later recovers automatically.

    private func startDiscovery() {
        outputIndex = nil
        pendingOutputs.removeAll()
        monitorOutputs.removeAll()
        get("/devices")
    }

    private func handleDiscoveryMessage(path: String?, obj: [String: Any]) {
        guard let path else { return }
        let comps = path.split(separator: "/").map(String.init)  // e.g. ["devices","0","outputs","4"]
        let isError = obj["error"] != nil
        let data = obj["data"] as? [String: Any]

        switch comps.count {
        case 1 where comps[0] == "devices":
            guard !isError, let children = data?["children"] as? [String: Any], !children.isEmpty else {
                writeLog("[UA] Discovery: no UA devices present — retrying")
                scheduleDiscoveryRetry()
                return
            }
            let ids = children.keys.compactMap { Int($0) }.sorted()
            if ids.count > 1 {
                writeLog("[UA] Discovery: \(ids.count) devices present \(ids); using first (picker TBD)")
            }
            deviceId = ids[0]
            get("/devices/\(deviceId)/outputs")

        case 3 where comps[0] == "devices" && comps[2] == "outputs":
            guard !isError, let children = data?["children"] as? [String: Any], !children.isEmpty else {
                writeLog("[UA] Discovery: no outputs on device \(deviceId) — retrying")
                scheduleDiscoveryRetry()
                return
            }
            pendingOutputs = children.keys.compactMap { Int($0) }.sorted()
            monitorOutputs.removeAll()
            probeNextOutput()

        case 4 where comps[0] == "devices" && comps[2] == "outputs":
            // Collect every monitor-role output; selection happens once all are probed.
            if !isError,
               let props = data?["properties"] as? [String: Any],
               (props["IOType"] as? [String: Any])?["value"] as? String == "Monitor",
               props["CRMonitorLevelTapered"] != nil,
               let n = Int(comps[3]) {
                monitorOutputs.append(n)
            }
            probeNextOutput()

        default:
            break
        }
    }

    private func probeNextOutput() {
        if !pendingOutputs.isEmpty {
            let n = pendingOutputs.removeFirst()
            get("/devices/\(deviceId)/outputs/\(n)")
            return
        }
        // Every output probed — choose the monitor bus.
        guard let chosen = monitorOutputs.first else {
            writeLog("[UA] Discovery: no monitor output found on device \(deviceId) — retrying")
            scheduleDiscoveryRetry()
            return
        }
        if monitorOutputs.count > 1 {
            // Unconfirmed on multi-monitor models — surface it instead of guessing silently.
            writeLog("[UA] Discovery: \(monitorOutputs.count) monitor outputs \(monitorOutputs); using first \(chosen) (picker TBD)")
        }
        finishDiscovery(outputIndex: chosen)
    }

    private func finishDiscovery(outputIndex n: Int) {
        guard outputIndex == nil else { return }
        outputIndex = n
        writeLog("[UA] Discovery: monitor output = /devices/\(deviceId)/outputs/\(n)")
        fetchInitialState()
        startHeartbeat()
    }

    private func scheduleDiscoveryRetry() {
        let gen = generation
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.generation == gen, self.isConnected, self.outputIndex == nil else { return }
            self.startDiscovery()
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, self.isConnected, let outputIndex = self.outputIndex else { return }
            self.get("/devices/\(self.deviceId)/outputs/\(outputIndex)")
            // Poll physical presence: the engine keeps the socket open when the
            // Apollo is unplugged, so DeviceOnline is the only reliable signal.
            self.get("/devices/\(self.deviceId)/DeviceOnline")
        }
        timer.resume()
        heartbeat = timer
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    // MARK: - Sending

    private func sendCommand(_ command: String) {
        guard let conn = connection, isConnected else {
            writeLog("[UA] Not connected — drop: \(command)")
            return
        }
        var data = command.data(using: .utf8) ?? Data()
        data.append(0)  // null terminator
        conn.send(content: data, completion: .contentProcessed { err in
            if let err = err { writeLog("[UA] Send error: \(err)") }
        })
    }

    private func nextFuncId() -> Int { funcId += 1; return funcId }

    private func outputPath(_ leaf: String) -> String? {
        guard let outputIndex else { return nil }
        return "/devices/\(deviceId)/outputs/\(outputIndex)/\(leaf)/value"
    }

    private func setProp(_ leaf: String, valueLiteral: String) {
        guard let path = outputPath(leaf) else {
            writeLog("[UA] No monitor output discovered yet — drop set \(leaf)")
            return
        }
        let id = nextFuncId()
        let cmd = "set \(path)?context_type=main&func_id=\(id) \(valueLiteral)"
        writeLog("[UA] -> \(cmd)")
        sendCommand(cmd)
    }

    private func subscribe(_ leaf: String) {
        guard let path = outputPath(leaf) else { return }
        sendCommand("sub \(path)")
    }

    private func get(_ path: String) {
        sendCommand("get \(path)")
    }

    // MARK: - Public API

    private func fetchInitialState() {
        guard let outputIndex else { return }
        get("/devices/\(deviceId)/outputs/\(outputIndex)")
        // Subscribe so external changes (physical knob, UAD Console) update us
        subscribe("CRMonitorLevelTapered")
        subscribe("Mute")
        subscribe("DimOn")
        // Hardware presence: DeviceOnline is NOT subscribable on this engine, so
        // seed it once here and re-poll it on every heartbeat (see startHeartbeat).
        get("/devices/\(deviceId)/DeviceOnline")
    }

    /// Set monitor level 0.0..1.0 (tapered scale)
    func setLevel(_ tapered: Double) {
        let v = max(0.0, min(1.0, tapered))
        setProp("CRMonitorLevelTapered", valueLiteral: String(v))
        monitorLevel = v
        onStateChanged?()
    }

    func adjustLevel(by delta: Double) {
        setLevel(monitorLevel + delta)
    }

    func setMute(_ muted: Bool) {
        setProp("Mute", valueLiteral: muted ? "true" : "false")
        isMuted = muted
        onStateChanged?()
    }

    func toggleMute() { setMute(!isMuted) }

    func setDim(_ on: Bool) {
        setProp("DimOn", valueLiteral: on ? "true" : "false")
        isDim = on
        onStateChanged?()
    }

    func toggleDim() { setDim(!isDim) }
}
