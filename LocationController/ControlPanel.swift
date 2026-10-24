import SwiftUI

struct ContentView: View {
    @StateObject private var model = Controller.shared
    @ObservedObject private var modern = Controller.shared.modern
    @State private var showingMap = false
    @State private var showingEditor = false
    @State private var creatingTrack = false
    @State private var confirmingRestart = false
    private var controls: Capabilities { modern.snapshot.capabilities }
    private var trackLocked: Bool { model.modernMode ? !controls.canChooseTrack : model.active }
    private var paceLocked: Bool { model.modernMode ? !controls.canEditPace : model.active }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("轨迹控制面板").font(.title2.bold())
                Picker("连接方式", selection: $model.modernMode) {
                    Text("iOS 27 · USB 直连").tag(true)
                    Text("LocationSimulator").tag(false)
                }.pickerStyle(.segmented).disabled(model.active || modern.hasSession)
                if model.modernMode {
                    HStack {
                        Picker("手机", selection: $modern.selected) {
                            Text("请选择手机").tag("")
                            ForEach(modern.devices) { phone in
                                Text("\(phone.name) · iOS \(phone.version)").tag(phone.id)
                            }
                        }.disabled(!controls.canConnect)
                        Button("刷新") { modern.refresh() }.disabled(!controls.canConnect)
                        Button("连接") { modern.connect() }.disabled(modern.selected.isEmpty || !controls.canConnect)
                    }
                    HStack {
                        Button("GPX 起点定位") {
                            if let point = model.track?.points.first { modern.locate(point) }
                        }.disabled(model.track == nil || !controls.canLocate)
                        Button("地图选点") { showingMap = true }.disabled(!controls.canLocate)
                        Spacer()
                        Button("准备镜像") { modern.connect(prepare: true) }
                            .disabled(modern.selected.isEmpty || !controls.canConnect)
                    }
                }
                HStack {
                    Button("选择 GPX…") { model.choose() }.disabled(trackLocked)
                    Button("编辑 GPX…") { creatingTrack = false; showingEditor = true }.disabled(trackLocked || model.document == nil)
                    Button("新建路线…") { creatingTrack = true; showingEditor = true }.disabled(trackLocked)
                    Text(model.file?.lastPathComponent ?? "未选择轨迹").lineLimit(1).truncationMode(.middle)
                }
                if let track = model.track {
                    Text(String(format: "%.3f 公里 · %d 个点", track.meters / 1000, track.points.count))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("每公里配速")
                    TextField("6:00", text: $model.pace).frame(width: 75).disabled(paceLocked)
                    Text("分:秒")
                    if let speed = model.speed {
                        Text(String(format: "%.2f km/h", speed)).foregroundStyle(.secondary)
                    }
                }
                Toggle("配速平滑波动", isOn: $model.variablePace).disabled(paceLocked)
                if model.variablePace {
                    HStack {
                        Text("±\(Int(model.effectiveAmplitude)) 秒/公里")
                        Slider(value: $model.amplitude, in: 5...30, step: 5)
                            .frame(width: 180).disabled(paceLocked)
                    }
                }
                HStack {
                    if model.modernMode {
                        if controls.canResume {
                            Button("继续") { model.perform(.resume) }
                                .buttonStyle(.borderedProminent).disabled(modern.snapshot.hasRoute && model.speed == nil)
                        } else {
                            Button("开始") { model.perform(.start) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!controls.canStart || model.track == nil || model.speed == nil)
                        }
                        Button("暂停") { model.perform(.pause) }.disabled(!controls.canPause)
                        Button("重新开始") { confirmingRestart = true }
                            .disabled(!controls.canRestart || model.speed == nil)
                        Button("恢复真实定位") { model.perform(.clear) }.disabled(!controls.canClear)
                    } else {
                        Button("开始") { model.perform(.start) }.buttonStyle(.borderedProminent)
                            .disabled(model.track == nil || model.speed == nil || model.active)
                        Button("停止移动") { model.perform(.pause) }.disabled(!model.hasSession)
                        Button("恢复真实定位") { model.perform(.clear) }.disabled(!model.hasSession)
                    }
                }
                if model.modernMode && modern.snapshot.hasRoute {
                    ProgressView(value: min(modern.snapshot.meters, modern.snapshot.total), total: max(1, modern.snapshot.total))
                    HStack {
                        Text(String(format: "%.3f / %.3f 公里", modern.snapshot.meters / 1000, modern.snapshot.total / 1000))
                        Spacer()
                        if let pace = modern.snapshot.pace {
                            Text("指令配速 \(Pace.label(pace))/公里")
                        }
                    }.font(.caption).monospacedDigit()
                }
                Text(model.modernMode ? modern.message : model.status)
                    .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }
        .frame(width: 650, height: 570)
        .disabled(model.busy || modern.busy)
        .sheet(isPresented: $showingMap) {
            MapPointPicker(initialCenter: modern.snapshot.position ?? model.track?.points.first) { point in
                modern.locate(point)
            }
        }
        .sheet(isPresented: $showingEditor) {
            GPXEditor(document: creatingTrack ? GPXDocument() : model.document ?? GPXDocument(), sourceURL: creatingTrack ? nil : model.file) { url, document in
                do { try model.load(url, document: document) }
                catch { modern.message = error.localizedDescription; model.status = error.localizedDescription }
            }
        }
        .confirmationDialog("从 GPX 起点重新开始？当前进度将清零。", isPresented: $confirmingRestart) {
            Button("从起点重新开始") { model.perform(.restart) }
        }
    }
}
