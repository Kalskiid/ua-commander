import Foundation
import Network

// Direct client for the UA Mixer Engine IPC protocol on localhost:4710.
// Protocol (reverse-engineered from packet capture):
//   client -> server: "<verb> <path>?<query> <value>\0"   (null-terminated text)
//   server -> client: '{"path":"...","parameters":{...},"data":...}\0' (JSON, null-terminated)
//   verbs observed: get, set, sub (subscribe), unsub
//
// Key paths for Apollo Twin X:
//   /devices/0/outputs/4/CRMonitorLevelTapered/value   float 0.0..1.0  (monitor level)
//   /devices/0/outputs/4/CRMonitorLevel/value          float -96..0 dB (read-only mirror)
//   /devices/0/outputs/4/Mute/value                    bool             (monitor mute)
//   /devices/0/outputs/4/DimOn/value                   bool             (dim toggle)
final class UAClient {
    private let host = NWEndpoint.Host("127.0.0.1")
    private let port: NWEndpoint.Port = 4710

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.user.apollocontroller.ua")
    private var funcId: Int = 1000
    private var rxBuffer = Data()

    // Current cached state
    private(set) var monitorLevel: Double = 0.5  // tapered 0..1
    private(set) var isMuted: Bool = false
    private(set) var isDim: Bool = false
    private(set) var isConnected: Bool = false

    var onStateChanged: (() -> Void)?

    // Output index to control. Apollo Twin X has the MONITOR on output 4 by default.
    private let outputIndex: Int

    init(outputIndex: Int = 4) {
        self.outputIndex = outputIndex
    }

    // MARK: - Connection lifecycle

    func connect() {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                writeLog("[UA] Connected to UA Mixer Engine on \(self.host):\(self.port)")
                self.isConnected = true
                self.startReceive()
                self.fetchInitialState()
            case .failed(let err):
                writeLog("[UA] Connection failed: \(err) — retrying in 3s")
                self.isConnected = false
                self.queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.reconnect() }
            case .cancelled:
                writeLog("[UA] Connection cancelled")
                self.isConnected = false
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func reconnect() {
        connection?.cancel()
        connection = nil
        connect()
    }

    private func startReceive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
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
            self.startReceive()
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

        if let err = obj["error"] as? String {
            writeLog("[UA] Server error: \(err) on \(obj["path"] ?? "?")")
            return
        }

        guard let path = obj["path"] as? String else { return }
        let value = obj["data"]

        switch path {
        case "/devices/0/outputs/\(outputIndex)/CRMonitorLevelTapered/value":
            if let d = value as? Double { monitorLevel = d; onStateChanged?() }
        case "/devices/0/outputs/\(outputIndex)/Mute/value":
            if let b = value as? Bool { isMuted = b; onStateChanged?() }
        case "/devices/0/outputs/\(outputIndex)/DimOn/value":
            if let b = value as? Bool { isDim = b; onStateChanged?() }
        case "/devices/0/outputs/\(outputIndex)":
            // Full state object (response to initial GET)
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

    private func outputPath(_ leaf: String) -> String {
        return "/devices/0/outputs/\(outputIndex)/\(leaf)/value"
    }

    private func setProp(_ leaf: String, valueLiteral: String) {
        let id = nextFuncId()
        let cmd = "set \(outputPath(leaf))?context_type=main&func_id=\(id) \(valueLiteral)"
        writeLog("[UA] -> \(cmd)")
        sendCommand(cmd)
    }

    private func subscribe(_ leaf: String) {
        let cmd = "sub \(outputPath(leaf))"
        sendCommand(cmd)
    }

    private func get(_ path: String) {
        sendCommand("get \(path)")
    }

    // MARK: - Public API

    private func fetchInitialState() {
        get("/devices/0/outputs/\(outputIndex)")
        // Subscribe so external changes (physical knob, UAD Console) update us
        subscribe("CRMonitorLevelTapered")
        subscribe("Mute")
        subscribe("DimOn")
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
