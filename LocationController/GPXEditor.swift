import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GPXEditor: View {
    @StateObject private var model: GPXEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var center: Coordinate?
    @State private var adding = false
    @State private var fitRequest = 0
    @State private var radius = 1.0
    @State private var confirmingClose = false
    let sourceURL: URL?
    let onSave: (URL, GPXDocument) -> Void

    init(document: GPXDocument, sourceURL: URL?, onSave: @escaping (URL, GPXDocument) -> Void) {
        _adding = State(initialValue: document.vertices.isEmpty)
        _model = StateObject(wrappedValue: GPXEditorModel(document: document))
        self.sourceURL = sourceURL
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GPX 编辑").font(.title2.bold())
                Spacer()
                Text(String(format: "%.3f 公里 · %d 个点", model.visibleDocument.track.meters / 1000, model.visibleDocument.vertices.count))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            MapLocationSearch(center: center ?? model.document.vertices.first?.coordinate) { center = $0 }
            HStack {
                Picker("工具", selection: $adding) {
                    Text("选择 / 拖动").tag(false)
                    Text("添加点").tag(true)
                }.pickerStyle(.segmented).frame(width: 240).disabled(model.preview != nil)
                Button("删除点") { model.deleteSelection() }.disabled(model.selected == nil || model.preview != nil)
                Button("撤销") { model.undo() }.disabled(!model.canUndo)
                Button("重做") { model.redo() }.disabled(!model.canRedo)
                Spacer()
                Button("显示全程") { center = nil; fitRequest += 1 }
            }
            GPXRouteMap(model: model, center: center, adding: adding, fitRequest: fitRequest)
                .frame(minHeight: 280, idealHeight: 360)
            Text(model.preview != nil ? "橙色为扰动预览" : adding ? "点击空白处添加点；选中点后，在其后插入" : "点击选择点，拖动调整；放大地图可编辑密集点")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("扰动幅度")
                Slider(value: Binding(get: { radius }, set: { value in
                    radius = value
                    if model.preview != nil { randomize() }
                }), in: 0.5...10, step: 0.5).frame(width: 150)
                Text(String(format: "%.1f 米", radius)).monospacedDigit().frame(width: 60)
                Button(model.preview == nil ? "随机扰动" : "重新随机") { randomize() }
                    .disabled(model.document.vertices.count < 2)
                if model.preview != nil {
                    Button("应用") { model.applyPreview() }
                    Button("取消扰动") { model.cancelPreview() }
                }
                Spacer()
            }
            HStack {
                Text(model.message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("取消") {
                    if model.hasChanges { confirmingClose = true } else { dismiss() }
                }
                Button("另存并载入…") { save() }.buttonStyle(.borderedProminent)
                    .disabled(model.document.vertices.count < 2 || model.preview != nil)
            }
        }
        .padding(20).frame(width: 860, height: 610)
        .interactiveDismissDisabled(model.hasChanges)
        .confirmationDialog("放弃未保存的编辑？", isPresented: $confirmingClose) {
            Button("放弃编辑", role: .destructive) { dismiss() }
        }
    }

    func randomize() {
        model.previewPerturbation(radius: radius, seed: UInt64.random(in: .min ... .max))
    }

    func save() {
        do {
            let data = try model.document.encoded()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
            panel.nameFieldStringValue = (sourceURL?.deletingPathExtension().lastPathComponent ?? "新路线") + "-edited.gpx"
            panel.directoryURL = sourceURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            onSave(url, model.document)
            dismiss()
        } catch { model.message = error.localizedDescription }
    }
}
