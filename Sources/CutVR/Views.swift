import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum Theme {
    static let bg = Color(red: 0.075, green: 0.075, blue: 0.085)        // window
    static let canvas = Color(red: 0.045, green: 0.045, blue: 0.052)    // behind the video
    static let panel = Color(red: 0.105, green: 0.105, blue: 0.12)      // edit area, inspector
    static let track = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let control = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.07)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let ok = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let warn = Color(red: 0.98, green: 0.78, blue: 0.30)
    static let blade = Color(red: 1.0, green: 0.45, blue: 0.40)
    static let text2 = Color.white.opacity(0.55)
    static let text3 = Color.white.opacity(0.35)
}

struct ContentView: View {
    @EnvironmentObject var model: EditorModel
    @EnvironmentObject var updater: Updater
    @State private var dropTargeted = false
    @AppStorage("showOverlay") private var showOverlay = true
    @AppStorage("muted") private var muted = false
    @AppStorage("singleEye") private var singleEye = false
    @AppStorage("showInspector") private var showInspector = true

    private var stereoLayout: StereoLayout? { StereoLayout.detect(model.vrInfo, size: model.videoSize) }
    private var shownEye: StereoLayout? { singleEye ? stereoLayout : nil }

    /// Aspect ratio of what is shown: the whole frame or one eye.
    private var previewAspect: CGFloat {
        guard model.videoSize.width > 0, model.videoSize.height > 0 else { return 16 / 9 }
        let r = model.videoSize.width / model.videoSize.height
        switch shownEye {
        case .sideBySide: return r / 2
        case .topBottom: return r * 2
        case nil: return r
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.url == nil {
                placeholder
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        viewer
                        Theme.hairline.frame(height: 1)
                        editArea
                    }
                    if showInspector {
                        Theme.hairline.frame(width: 1)
                        InspectorView()
                    }
                }
            }
            Theme.hairline.frame(height: 1)
            StatusBar()
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .navigationTitle("CutVR")
        .navigationSubtitle(model.url?.lastPathComponent ?? "Lossless VR video cutter")
        .toolbar { toolbar }
        .toolbarBackground(Theme.bg, for: .windowToolbar)
        .onAppear { model.player.isMuted = muted }
        .onChange(of: muted) { _, value in model.player.isMuted = value }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in await model.open(url) } }
            }
            return true
        }
        .overlay(dropTargeted ? RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 2).padding(6) : nil)
        .alert("Error", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") {}
        } message: { Text(model.error ?? "") }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            updateBadge
            if model.url != nil {
                HeadsetPill(status: HeadsetStatus(model))
                    .onTapGesture { showInspector = true }
            }
            Button { openPanel() } label: { Label("Open", systemImage: "folder") }
                .keyboardShortcut("o")
                .help("Open a video (⌘O)")
            Button { model.chooseDestinationAndExport() } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(BarButtonStyle(prominent: true))
            .keyboardShortcut("s")
            .disabled(model.url == nil || model.clips.isEmpty || model.isExporting)
            .help("Export the clips joined together, VR headset metadata included (⌘S)")
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .keyboardShortcut("i", modifiers: [])
                .disabled(model.url == nil)
                .help("Show or hide the inspector (I)")
        }
    }

    @ViewBuilder private var updateBadge: some View {
        if updater.isInstalling {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.system(size: 11, weight: .semibold))
            }
        } else if let release = updater.available {
            Button { updater.promptInstall() } label: {
                Label("Update \(release.version)", systemImage: "arrow.down.circle.fill")
            }
            .labelStyle(.titleAndIcon)
            .tint(Theme.accent)
            .disabled(model.isExporting)
            .help("A new version of CutVR is available on GitHub")
        }
    }

    // MARK: Viewer

    private var viewer: some View {
        VStack(spacing: 14) {
            // aspectRatio comes last so the clip, border and overlay hug the visible picture.
            PlayerView(player: model.player, singleEye: shownEye)
                .overlay(alignment: .topLeading) {
                    if showOverlay { HeadsetOverlay().padding(10) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                .aspectRatio(previewAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            transport
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    /// Playback controls and view options in one floating bar under the picture.
    private var transport: some View {
        HStack(spacing: 4) {
            Button { model.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("Previous frame (←)")
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / pause (Space)")
            Button { model.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("Next frame (→)")

            barDivider

            HStack(spacing: 6) {
                Text(EditorModel.timecode(model.current)).foregroundStyle(.white)
                Text("/").foregroundStyle(Theme.text3)
                Text(EditorModel.timecode(model.editDuration)).foregroundStyle(Theme.text2)
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .padding(.horizontal, 6)

            barDivider

            Button { singleEye.toggle() } label: { Image(systemName: singleEye ? "rectangle" : "rectangle.split.2x1") }
                .buttonStyle(IconButtonStyle(active: singleEye))
                .keyboardShortcut("e", modifiers: [])
                .disabled(stereoLayout == nil)
                .help(stereoLayout == nil ? "Single view is only for stereo (side-by-side or top-bottom) video"
                                          : "Single view: show one eye only (E)")
            Button { muted.toggle() } label: { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                .buttonStyle(IconButtonStyle(active: muted))
                .keyboardShortcut("m", modifiers: [])
                .help(muted ? "Unmute (M)" : "Mute (M)")
            Button { showOverlay.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(IconButtonStyle(active: showOverlay))
                .keyboardShortcut("h", modifiers: [])
                .help("Show headset parameters over the video (H)")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .disabled(model.isExporting)
    }

    private var barDivider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 6)
    }

    // MARK: Edit area

    private var editArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    toolButton(.select, icon: "cursorarrow", key: "v", help: "Select tool (V) – click a clip to select it")
                    toolButton(.blade, icon: "scissors", key: "b", help: "Scissors tool (B) – click the timeline to cut")
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.control))

                Button { Task { await model.splitAtPlayhead() } } label: { Label("Cut", systemImage: "scissors") }
                    .buttonStyle(BarButtonStyle())
                    .keyboardShortcut("c", modifiers: [])
                    .help("Cut at the playhead (C) – snaps back to the nearest keyframe")
                Button { model.deleteSelected() } label: { Label("Delete Clip", systemImage: "trash") }
                    .buttonStyle(BarButtonStyle())
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(model.selectedClip == nil)
                    .help("Delete the selected clip (⌫) – the rest closes up")
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(BarButtonStyle())
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                    .help("Undo (⌘Z)")

                Spacer()
                Text(hint).font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            TimelineView()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .background(Theme.panel)
        .disabled(model.isExporting)
    }

    private var hint: String {
        if model.tool == .blade { return "Click the timeline to cut" }
        if model.selectedClip != nil { return "Press ⌫ to delete the selected clip" }
        return model.clips.count > 1 ? "Click a clip to select it" : "Press C to cut at the playhead"
    }

    private func toolButton(_ tool: EditTool, icon: String, key: KeyEquivalent, help: String) -> some View {
        Button { model.tool = tool } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 32, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(model.tool == tool ? Theme.accent : .clear))
                .foregroundStyle(model.tool == tool ? .white : Theme.text2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .help(help)
    }

    // MARK: Empty state

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "visionpro")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            VStack(spacing: 6) {
                Text("Drop a VR video here").font(.system(size: 20, weight: .semibold))
                Text("MP4 or MOV · lossless cuts · headset metadata preserved")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            Button { openPanel() } label: { Label("Open Video…", systemImage: "folder") }
                .buttonStyle(BarButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .foregroundStyle(dropTargeted ? Theme.accent : Color.white.opacity(0.14))
                .padding(24)
        )
        .background(Theme.canvas)
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

// MARK: - Inspector

struct InspectorView: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headsetCard
                section("Video") {
                    row("Resolution", Describe.resolution(model))
                    row("Frame rate", Describe.frameRate(model))
                    row("Codec", Describe.codec(model.codec))
                    row("Bitrate", Describe.bitrate(model))
                }
                section("VR format") {
                    row("Layout", Describe.layout(model))
                    row("Projection", Describe.projection(model))
                    row("Name tags", Describe.nameTags(model))
                }
                section("Edit") {
                    row("Clips", "\(model.clips.count)")
                    row("Result", EditorModel.timecode(model.editDuration), Theme.accent)
                    row("Removed", EditorModel.timecode(max(0, model.duration - model.editDuration)))
                    row("Original", EditorModel.timecode(model.duration))
                }
                section("Export") {
                    Text("Lossless stream copy into the same container. Cuts start on keyframes.")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .frame(width: 270)
        .background(Theme.panel)
    }

    private var headsetCard: some View {
        let status = HeadsetStatus(model)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.icon).foregroundStyle(status.color)
                Text(status.title).font(.system(size: 13, weight: .semibold))
            }
            Text(status.detail)
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            if canAddVR { addVRPicker }
            if let entries = model.vrInfo?.entries, !entries.isEmpty {
                DisclosureGroup("\(entries.count) metadata entries") {
                    Text(entries.joined(separator: "\n"))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.system(size: 11))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(status.color.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(status.color.opacity(0.25)))
    }

    /// Writing VR metadata needs MP4/MOV and a source without any of its own.
    private var canAddVR: Bool {
        guard let info = model.vrInfo, !info.hasEmbedded, let ext = model.url?.pathExtension.lowercased() else { return false }
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    private var addVRPicker: some View {
        let suggested = VRFormat.suggested(for: model.videoSize)
        return VStack(alignment: .leading, spacing: 6) {
            Text("VR format to write on export")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            Picker("VR format", selection: $model.addVR) {
                Text("Don't add").tag(VRFormat?.none)
                Divider()
                ForEach(VRFormat.allCases) { f in
                    Text(f.title).tag(VRFormat?.some(f))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(model.isExporting)
            if model.addVR == nil, let suggested {
                Button("Use \(suggested.title)") { model.addVR = suggested }
                    .buttonStyle(BarButtonStyle(compact: true))
                    .help("Frame shape 2:1 – two square eyes side by side, the usual VR180 layout")
            }
        }
        .padding(.top, 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Theme.text3)
            content()
        }
    }

    private func row(_ k: String, _ v: String, _ color: Color = .white) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            Text(v).foregroundStyle(color).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.system(size: 12).monospacedDigit())
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var model: EditorModel
    @State private var showMissing = false

    var body: some View {
        HStack(spacing: 10) {
            content
            Spacer(minLength: 12)
            Link(destination: URL(string: "https://hesse.works")!) {
                Text("by ").foregroundStyle(Theme.text3) + Text("hesse.works").foregroundStyle(Theme.text2)
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Theme.bg)
    }

    @ViewBuilder private var content: some View {
        if model.isExporting {
            ProgressView(value: model.exportProgress).frame(width: 180)
            Text(model.exportStatus).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            Button("Cancel") { model.cancelExport() }.buttonStyle(BarButtonStyle(compact: true))
        } else if let r = model.report {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.ok ? Theme.ok : .orange)
            Text(r.message).font(.system(size: 11)).lineLimit(1).truncationMode(.tail).help(r.message)
            if !r.missing.isEmpty {
                Button("\(r.missing.count) missing") { showMissing = true }
                    .buttonStyle(BarButtonStyle(compact: true))
                    .popover(isPresented: $showMissing) {
                        Text(r.missing.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                    }
            }
            if let out = r.outputURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                    .buttonStyle(BarButtonStyle(compact: true))
            }
        } else if model.url != nil {
            Label("Lossless · keyframe-accurate · VR metadata preserved", systemImage: "bolt.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
        } else {
            Text("Ready").font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
    }
}

// MARK: - Small components

struct HeadsetPill: View {
    let status: HeadsetStatus

    var body: some View {
        HStack(spacing: 5) {
            if case .checking = status { ProgressView().controlSize(.mini) } else { Image(systemName: status.icon) }
            Text(status.short)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(status.color.opacity(0.15)))
        .help(status.detail)
    }
}

/// Rounded text button for the edit bar and status bar.
struct BarButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, prominent: prominent, compact: compact)
    }

    private struct Styled: View {
        let configuration: Configuration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .padding(.horizontal, compact ? 8 : 11)
                .frame(height: compact ? 22 : 28)
                .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.9))
                .background(RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous).fill(fill))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            if prominent { return Theme.accent.opacity(pressed ? 0.7 : hover ? 0.9 : 1) }
            return Color.white.opacity(pressed ? 0.16 : hover && enabled ? 0.11 : 0.07)
        }
    }
}

/// Square icon button for the transport bar; `active` marks a switched-on option.
struct IconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, active: active)
    }

    private struct Styled: View {
        let configuration: Configuration
        let active: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(active ? Theme.accent : Color.white.opacity(0.85))
                .background(Circle().fill(fill))
                .opacity(enabled ? 1 : 0.3)
                .contentShape(Circle())
                .onHover { hover = $0 }
        }

        private var fill: Color {
            if configuration.isPressed { return Color.white.opacity(0.18) }
            if active { return Theme.accent.opacity(0.16) }
            return hover && enabled ? Color.white.opacity(0.1) : .clear
        }
    }
}
