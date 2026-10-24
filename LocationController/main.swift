import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

enum PlaybackAction { case start, pause, resume, restart, clear }

@MainActor final class Controller: ObservableObject {
    static let shared = Controller()
    let modern = ModernBackend()
    @Published var modernMode = true
    @Published var file: URL?
    @Published var document: GPXDocument?
    var track: Track? { document?.track }
    @Published var pace = UserDefaults.standard.string(forKey: "pace") ?? "6:00"
    @Published var status = "先在 LocationSimulator 中连接并选中手机。"
    @Published var busy = false
    @Published var variablePace = UserDefaults.standard.bool(forKey: "variablePace")
    @Published var amplitude = UserDefaults.standard.object(forKey: "amplitude") as? Double ?? 15
    @Published var active = false
    @Published var currentPace: Double?
    @Published var hasSession = false
    private var targetWindow: Int?
    private var targetDevice: String?
    private var monitor: Task<Void, Never>?
    private var runToken = UUID()
    private var activity: NSObjectProtocol?
    var speed: Double? { Pace.seconds(pace).map { 3600 / $0 } }
    var effectiveAmplitude: Double { guard let base = Pace.seconds(pace) else { return 0 }; return max(0, min(amplitude, base - 60, 3600 - base)) }
    init() {
        let defaults = UserDefaults.standard
        if let window = defaults.object(forKey: "sessionWindow") as? Int, let device = defaults.string(forKey: "sessionDevice") {
            targetWindow = window; targetDevice = device; hasSession = true
            status = "找到上次设备记录。可停止移动或恢复定位；不会自动恢复变速。"
        }
        if let path = defaults.string(forKey: "lastGPX"), let parsed = try? GPXDocument(data: Data(contentsOf: URL(fileURLWithPath: path))) {
            file = URL(fileURLWithPath: path); document = parsed
        }
    }
    func cancelMonitor() {
        runToken = UUID(); monitor?.cancel(); monitor = nil; active = false; currentPace = nil
        if let activity = activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    func saveSession() {
        UserDefaults.standard.set(targetWindow, forKey: "sessionWindow")
        UserDefaults.standard.set(targetDevice, forKey: "sessionDevice")
        hasSession = targetWindow != nil && targetDevice != nil
    }
    func startMonitor(base: Double, amplitude: Double, duration: Double) {
        let profile = PaceProfile(base: base, amplitude: amplitude, duration: duration)
        let start = ProcessInfo.processInfo.systemUptime
        let token = runToken
        active = true; currentPace = base
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "正在播放 GPX 轨迹")
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                guard let self = self, self.runToken == token, let wid = self.targetWindow, let device = self.targetDevice else { return }
                if self.busy { continue }
                let seconds = profile.seconds(at: ProcessInfo.processInfo.systemUptime - start)
                let update = amplitude > 0 ? "set speed of w to \(3600 / seconds)" : ""
                let script = """
                tell application "LocationSimulator"
                    set w to first window whose id is \(wid)
                    if selected device of w is missing value then error "设备已断开。"
                    if id of selected device of w is not \(Self.quoted(device)) then error "所选设备已改变，配速更新已停止。"
                    set mv to map view of w
                    if not (follows route of mv) then return "DONE"
                    \(update)
                    return "RUNNING"
                end tell
                """
                self.busy = true
                do {
                    let result = try await Task.detached { try runAppleScript(script) }.value
                    self.busy = false
                    guard self.runToken == token else { return }
                    if result.trimmingCharacters(in: .whitespacesAndNewlines) == "DONE" {
                        self.cancelMonitor()
                        self.status = "导航已结束或被原软件停止。模拟位置可能保留，请按需恢复真实定位。"
                        return
                    }
                    self.currentPace = seconds
                } catch {
                    self.busy = false
                    guard self.runToken == token else { return }
                    self.cancelMonitor()
                    self.status = "监测/变速已停止：\(error.localizedDescription) 原软件可能仍在导航，请检查或点击停止。"
                    return
                }
            }
        }
    }
    func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK, let url=panel.url else { return }
        do { try load(url, document: GPXDocument(data: Data(contentsOf: url))) }
        catch {
            if modernMode { modern.message = error.localizedDescription }
            else { status = error.localizedDescription }
        }
    }
    func load(_ url: URL, document: GPXDocument) throws {
        guard modern.snapshot.capabilities.canChooseTrack, !active else { throw Failure("请先结束当前路线，再载入编辑结果。") }
        self.document = document
        file = url
        UserDefaults.standard.set(url.path, forKey: "lastGPX")
        status = "轨迹已载入，开始后将移动到轨迹起点。"
        if modernMode { modern.message = status }
    }
    private func savePacePreferences() {
        UserDefaults.standard.set(pace, forKey: "pace")
        UserDefaults.standard.set(variablePace, forKey: "variablePace")
        UserDefaults.standard.set(amplitude, forKey: "amplitude")
    }
    static func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }
    func perform(_ action: PlaybackAction) {
        if modernMode {
            if action == .pause { modern.pause(); return }
            if action == .clear { modern.clear(); return }
            if action == .resume && !modern.snapshot.hasRoute { modern.resume(); return }
            guard let seconds = Pace.seconds(pace) else {
                modern.message = "请输入有效配速，例如 6:00。"
                return
            }
            savePacePreferences()
            let variation = variablePace ? effectiveAmplitude : 0
            switch action {
            case .start:
                guard let track = track else { modern.message = "请先选择 GPX。"; return }
                modern.start(track.points, pace: seconds, amplitude: variation)
            case .resume: modern.resume(pace: seconds, amplitude: variation)
            case .restart: modern.restart(pace: seconds, amplitude: variation)
            default: break
            }
            return
        }
        guard !busy else { return }
        if action != .start { cancelMonitor() }
        let script: String
        if action == .start {
            guard let t=track, let kmh=speed else { status="请选 GPX，并按 分:秒 输入配速，例如 6:00。"; return }
            let coords=t.points.map { "{\($0.latitude), \($0.longitude)}" }.joined(separator: ",")
            script="""
            tell application "LocationSimulator"
                if (count of windows) = 0 then error "请先打开 LocationSimulator 主窗口。"
                set w to first window
                if selected device of w is missing value then error "请先在 LocationSimulator 中选中已连接的手机。"
                set mv to map view of w
                if mv is missing value then error "设备地图尚未就绪。"
                if follows route of mv or move automatically of mv then error "当前设备正在移动，请先停止原有导航。"
                set transport type of w to walk
                set speed of w to \(kmh)
                set navigate back automatically of mv to false
                follow mv route {\(coords)}
                if not (follows route of mv) then error "导航未启动，请检查手机连接和开发者镜像。"
                return (id of w as text) & "|" & (id of selected device of w)
            end tell
            """
        } else {
            guard let wid=targetWindow, let device=targetDevice else { status="尚未通过此面板启动；已有导航请在原软件中停止。"; return }
            let action = action == .clear ? "reset location mv" : "set p to current location of mv\nif p is missing value then error \"设备当前位置不可用。\"\nset current location of mv to p"
            script="""
            tell application "LocationSimulator"
                set w to first window whose id is \(wid)
                if selected device of w is missing value then error "设备已断开。"
                if id of selected device of w is not \(Self.quoted(device)) then error "所选设备已改变，请回到原设备后重试。"
                set mv to map view of w
                set move automatically of mv to false
                \(action)
                if follows route of mv then error "导航仍在进行，请在原软件中检查。"
                return "OK"
            end tell
            """
        }
        busy=true; status="正在\(action == .start ? "开始" : action == .pause ? "停止" : "恢复定位")…"
        Task {
            do {
                let output = try await Task.detached { try runAppleScript(script) }.value
                if action == .start {
                    let parts=output.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:"|",maxSplits:1)
                    guard parts.count==2, let wid=Int(parts[0]) else { throw Failure("软件返回了未知结果，请到原软件检查导航状态。") }
                    targetWindow=wid; targetDevice=String(parts[1]); saveSession()
                    savePacePreferences()
                    if let base = Pace.seconds(pace), let track = track {
                        startMonitor(base: base, amplitude: variablePace ? effectiveAmplitude : 0, duration: track.meters / (3600 / (base + effectiveAmplitude) / 3.6))
                    }
                    status="已发送开始命令。可在原软件中查看进度；结束后点“恢复真实定位”。"
                } else {
                    if action == .clear { targetWindow = nil; targetDevice = nil; saveSession() }
                    status = action == .pause ? "已停止移动，保留当前模拟位置。" : "已发送定位重置命令，请在手机地图确认。" }
            } catch { status=error.localizedDescription }
            busy=false
        }
    }
}
func runAppleScript(_ script: String) throws -> String {
    let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/osascript"); process.arguments=["-"]
    let input=Pipe(), output=Pipe(), errors=Pipe(); process.standardInput=input; process.standardOutput=output; process.standardError=errors
    try process.run()
    let group=DispatchGroup(); let box=OutputBox()
    group.enter(); DispatchQueue.global().async { box.output=output.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter(); DispatchQueue.global().async { box.error=errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    input.fileHandleForWriting.write(Data(("with timeout of 15 seconds\n" + script + "\nend timeout").utf8)); try? input.fileHandleForWriting.close()
    process.waitUntilExit(); group.wait()
    guard process.terminationStatus==0 else { throw Failure(String(data:box.error,encoding:.utf8) ?? "自动化命令失败。") }
    return String(data:box.output,encoding:.utf8) ?? ""
}
final class OutputBox: @unchecked Sendable { var output=Data(); var error=Data() }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        let model = Controller.shared
        if model.active || model.busy || model.modern.hasSession || model.modern.busy {
            let alert = NSAlert()
            alert.messageText = "结束设备会话并退出？"
            alert.informativeText = model.modernMode ? "将尝试停止播放并恢复真实定位。请保持数据线连接；连接已中断时可能无法恢复。" : "退出后将停止配速更新，但 LocationSimulator 可能继续导航。建议先恢复真实定位。"
            alert.addButton(withTitle: "返回面板")
            alert.addButton(withTitle: "结束并退出")
            if alert.runModal() != .alertSecondButtonReturn { return .terminateCancel }
        }
        terminating = true
        Task {
            let restored = await model.modern.shutdown()
            if !restored {
                let alert = NSAlert()
                alert.messageText = "未能确认恢复真实定位"
                alert.informativeText = "请检查手机地图；可重新连接后点击恢复真实定位。"
                alert.addButton(withTitle: "返回面板")
                alert.addButton(withTitle: "仍然退出")
                if alert.runModal() != .alertSecondButtonReturn {
                    terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
@main struct LocationControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Window("轨迹控制面板", id: "main") { ContentView() }.windowResizability(.contentSize) }
}
