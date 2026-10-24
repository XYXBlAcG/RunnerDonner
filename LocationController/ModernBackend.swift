import Foundation

struct Phone: Identifiable {
    let id: String
    let name: String
    let version: String
}

extension SessionSnapshot {
    static let disconnected = SessionSnapshot(
        state: .disconnected, capabilities: Capabilities(), meters: 0, total: 0,
        pace: nil, position: nil, reconnects: 0, hasRoute: false
    )
}

@MainActor final class ModernBackend: ObservableObject {
    @Published var devices: [Phone] = []
    @Published var selected = ""
    @Published var snapshot = SessionSnapshot.disconnected
    @Published var message = "请连接手机，然后刷新设备。"
    @Published var busy = false
    var hasSession: Bool { snapshot.position != nil }
    private var process: Process?
    private var input: FileHandle?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private let reader = LineReader()
    private var activity: NSObjectProtocol?

    func ensureStarted() throws {
        if let process = process, process.isRunning { return }
        let executable = Bundle.main.resourceURL!.appendingPathComponent("DeviceBridge/DeviceBridge")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure("找不到设备后端，请使用完整应用包。")
        }
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        reader.reset()
        stdout.fileHandleForReading.readabilityHandler = { [weak self, reader] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            let lines = reader.append(bytes)
            Task { @MainActor [weak self] in
                for line in lines { self?.receive(line) }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                guard let self = self, self.process === terminated else { return }
                self.message = "设备后端已退出，请重连后确认定位状态。"
                self.snapshot.state = .disconnected
                self.snapshot.capabilities = Capabilities()
                self.releaseActivity()
                self.failPending("设备后端已退出。")
            }
        }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
    }

    private func failPending(_ message: String) {
        let waits = pending
        pending.removeAll()
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        for continuation in waits.values { continuation.resume(throwing: Failure(message)) }
    }

    private func receive(_ data: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            message = "设备后端返回了无效数据。"
            failPending(message)
            return
        }
        if let id = value["id"] as? String, let continuation = pending.removeValue(forKey: id) {
            timeouts.removeValue(forKey: id)?.cancel()
            if value["ok"] as? Bool == true {
                continuation.resume(returning: value["result"] as? [String: Any] ?? [:])
            } else {
                continuation.resume(throwing: Failure(value["error"] as? String ?? "设备命令失败。"))
            }
            return
        }
        if value["event"] as? String == "warning" {
            message = value["message"] as? String ?? "恢复定位未确认。"
        }
        guard value["event"] as? String == "status" else { return }
        do {
            snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
            if let message = value["message"] as? String { self.message = message }
            if snapshot.capabilities.needsWakeLock {
                if activity == nil {
                    activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "设备定位会话进行中")
                }
            } else {
                releaseActivity()
            }
        } catch {
            message = "设备协议不匹配，请使用同一个完整应用包。"
            failPending(message)
        }
    }

    func releaseActivity() {
        if let activity = activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func request(_ command: DeviceCommand, _ parameters: [String: Any] = [:], timeout: UInt64 = 50) async throws -> [String: Any] {
        try ensureStarted()
        let id = UUID().uuidString
        var body = parameters
        body["id"] = id
        body["command"] = command.rawValue
        var data = try JSONSerialization.data(withJSONObject: body)
        data.append(10)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: timeout * 1_000_000_000) } catch { return }
                guard let self = self, let waiter = self.pending.removeValue(forKey: id) else { return }
                self.timeouts.removeValue(forKey: id)
                waiter.resume(throwing: Failure("设备命令等待超时，请检查手机和数据线。"))
            }
            do {
                guard let input = input else { throw Failure("设备后端未连接。") }
                try input.write(contentsOf: data)
            } catch {
                pending.removeValue(forKey: id)?.resume(throwing: error)
                timeouts.removeValue(forKey: id)?.cancel()
            }
        }
    }

    func refresh() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await request(.devices)
                devices = (result["devices"] as? [[String: Any]] ?? []).compactMap { value in
                    guard let id = value["id"] as? String else { return nil }
                    return Phone(id: id, name: value["name"] as? String ?? "iPhone", version: value["version"] as? String ?? "")
                }
                if !devices.contains(where: { $0.id == selected }) { selected = devices.first?.id ?? "" }
                message = devices.isEmpty ? "未发现 USB 手机，请检查连接并解锁。" : "请选择手机后连接。"
            } catch { message = error.localizedDescription }
        }
    }

    func connect(prepare: Bool = false) {
        guard !selected.isEmpty else { return }
        submit(.connect, ["device": selected, "prepare": prepare], timeout: prepare ? 720 : 50)
    }

    func locate(_ point: Coordinate) {
        submit(.locate, ["point": [point.latitude, point.longitude]])
    }

    func start(_ points: [Coordinate], pace: Double, amplitude: Double) {
        submit(.start, ["points": points.map { [$0.latitude, $0.longitude] }, "pace": pace, "amplitude": amplitude])
    }

    func resume(pace: Double? = nil, amplitude: Double? = nil) {
        var parameters: [String: Any] = [:]
        if let pace = pace { parameters["pace"] = pace }
        if let amplitude = amplitude { parameters["amplitude"] = amplitude }
        submit(.resume, parameters)
    }

    func restart(pace: Double, amplitude: Double) {
        submit(.restart, ["pace": pace, "amplitude": amplitude])
    }

    func pause() { submit(.pause) }
    func clear() { submit(.clear) }

    private func submit(_ command: DeviceCommand, _ parameters: [String: Any] = [:], timeout: UInt64 = 50) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { _ = try await request(command, parameters, timeout: timeout) }
            catch { message = error.localizedDescription }
        }
    }

    func shutdown() async -> Bool {
        guard process?.isRunning == true else { return !hasSession }
        let result = try? await request(.shutdown, timeout: 60)
        try? input?.close()
        input = nil
        releaseActivity()
        return result?["restored"] as? Bool == true
    }
}

final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    func append(_ bytes: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(bytes)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 10) {
            lines.append(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}
