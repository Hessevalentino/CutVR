import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum Theme {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let track = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let ok = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let blade = Color(red: 1.0, green: 0.45, blue: 0.40)
    static let text2 = Color.white.opacity(0.55)
}

struct ContentView: View {
    @EnvironmentObject var model: EditorModel
    @State private var dropTargeted = false
    @AppStorage("showOverlay") private var showOverlay = true

    var body: some View {
        VStack(spacing: 14) {
            header
            if model.url == nil {
                placeholder
            } else {
                PlayerView(player: model.player)
                    .aspectRatio(model.videoSize.width > 0 ? model.videoSize.width / model.videoSize.height : 16 / 9,
                                 contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        if showOverlay { HeadsetOverlay().padding(8) }
                    }
                    .frame(maxWidth: 520, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
                    .frame(maxWidth: .infinity)
                controls
                TimelineView()
                footer
            }
        }
        .padding(18)
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in await model.open(url) } }
            }
            return true
        }
        .overlay(dropTargeted ? RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 2).padding(4) : nil)
        .alert("Error", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("CutVR").font(.system(size: 18, weight: .bold))
                Link("by hesse.works", destination: URL(string: "https://hesse.works")!)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text2)
            }
            if let url = model.url {
                Text(url.lastPathComponent).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            vrBadge
            if model.url != nil {
                Toggle(isOn: $showOverlay) { Image(systemName: "visionpro") }
                    .toggleStyle(.button)
                    .keyboardShortcut("h", modifiers: [])
                    .help("Show headset parameters over the video (H)")
            }
            Button("Open…") { openPanel() }.keyboardShortcut("o")
        }
    }

    @ViewBuilder private var vrBadge: some View {
        if let info = model.vrInfo {
            let embedded = info.hasEmbedded
            let label = embedded ? "VR metadata: \(info.entries.count)"
                                 : (info.filenameTags.isEmpty ? "No VR metadata" : "VR in file name only")
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(embedded ? Theme.ok.opacity(0.18) : Color.orange.opacity(0.18)))
                .foregroundStyle(embedded ? Theme.ok : .orange)
                .help(badgeHelp(info))
        } else if model.url != nil {
            ProgressView().controlSize(.small)
        }
    }

    private func badgeHelp(_ info: VRInfo) -> String {
        var lines = info.entries
        if !info.filenameTags.isEmpty { lines.append("File name tags: " + info.filenameTags.joined(separator: ", ")) }
        if lines.isEmpty { lines = ["The file contains no st3d/sv3d or Google Spherical metadata."] }
        return lines.joined(separator: "\n")
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "visionpro").font(.system(size: 44)).foregroundStyle(Theme.text2)
            Text("Drop a VR video here or open one").foregroundStyle(Theme.text2)
            Button("Open Video…") { openPanel() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            // tools
            HStack(spacing: 2) {
                toolButton(.select, icon: "cursorarrow", key: "v", help: "Select tool (V) – click a clip to select it")
                toolButton(.blade, icon: "scissors", key: "b", help: "Scissors tool (B) – click the timeline to cut")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panel))

            Divider().frame(height: 18)

            Button { model.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 22)
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { model.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                .keyboardShortcut(.rightArrow, modifiers: [])

            Divider().frame(height: 18)

            Button { Task { await model.splitAtPlayhead() } } label: { Label("Cut", systemImage: "scissors") }
                .keyboardShortcut("c", modifiers: [])
                .help("Cut at the playhead (C) – snaps back to the nearest keyframe")
            Button { model.deleteSelected() } label: { Label("Delete Clip", systemImage: "trash") }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedClip == nil)
                .help("Delete the selected clip (⌫) – the rest closes up")
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
                .help("Undo (⌘Z)")

            Spacer()
            Text("\(EditorModel.timecode(model.current)) / \(EditorModel.timecode(model.editDuration))")
                .font(.system(size: 12, design: .monospaced))
        }
        .disabled(model.isExporting)
    }

    private func toolButton(_ tool: EditTool, icon: String, key: KeyEquivalent, help: String) -> some View {
        Button { model.tool = tool } label: {
            Image(systemName: icon)
                .frame(width: 30, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(model.tool == tool ? Theme.accent : .clear))
                .foregroundStyle(model.tool == tool ? .white : Theme.text2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .help(help)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                infoField("Clips", "\(model.clips.count)", .white)
                infoField("Result", EditorModel.timecode(model.editDuration), Theme.accent)
                infoField("Original", EditorModel.timecode(model.duration), Theme.text2)
                Spacer()
                if model.isExporting {
                    Button("Cancel") { model.cancelExport() }
                } else {
                    Button { model.chooseDestinationAndExport() } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut("s")
                    .disabled(model.clips.isEmpty)
                    .help("Export the clips joined together, VR headset metadata included (⌘S)")
                }
            }
            if model.isExporting {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: model.exportProgress)
                    Text(model.exportStatus).font(.caption).foregroundStyle(Theme.text2)
                }
            } else if let r = model.report {
                reportView(r)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }

    private func infoField(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 13, design: .monospaced))
        }
    }

    private func reportView(_ r: ExportReport) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.ok ? Theme.ok : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.message).font(.callout).textSelection(.enabled)
                ForEach(r.missing, id: \.self) { Text("missing: \($0)").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            if let out = r.outputURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.open(url) }
        }
    }
}
