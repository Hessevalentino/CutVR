import SwiftUI
import AVFoundation

/// Human-readable descriptions of the loaded video, shared by the inspector and the preview overlay.
@MainActor
enum Describe {
    static func resolution(_ m: EditorModel) -> String {
        m.videoSize.width > 0 ? "\(Int(m.videoSize.width)) × \(Int(m.videoSize.height))" : "–"
    }

    static func frameRate(_ m: EditorModel) -> String { String(format: "%.2f fps", m.frameRate) }

    static func bitrate(_ m: EditorModel) -> String {
        m.bitrate > 0 ? String(format: "%.1f Mbps", m.bitrate / 1_000_000) : "–"
    }

    static func codec(_ fourCC: String) -> String {
        let names = ["avc1": "H.264", "avc3": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "dvh1": "Dolby Vision",
                     "av01": "AV1", "vp09": "VP9", "apcn": "ProRes 422", "apch": "ProRes 422 HQ", "ap4h": "ProRes 4444"]
        guard !fourCC.isEmpty else { return "–" }
        return names[fourCC].map { "\($0) (\(fourCC))" } ?? fourCC
    }

    static func layout(_ m: EditorModel) -> String {
        if let s = m.vrInfo?.stereoMode { return s }
        // Guess from frame shape when nothing is embedded.
        let ratio = m.videoSize.height > 0 ? m.videoSize.width / m.videoSize.height : 0
        if ratio > 1.8 && ratio < 2.2 { return "side by side (guess)" }
        if ratio > 0.9 && ratio < 1.1 { return "top-bottom or mono (guess)" }
        return "unknown"
    }

    static func projection(_ m: EditorModel) -> String { m.vrInfo.map { $0.projection ?? "not set" } ?? "…" }

    static func nameTags(_ m: EditorModel) -> String {
        m.vrInfo.map { $0.filenameTags.isEmpty ? "none" : $0.filenameTags.map { "_" + $0 }.joined(separator: " ") } ?? "…"
    }
}

/// How a headset player will recognise the video.
enum HeadsetStatus {
    case checking, embedded(Int), willAdd(VRFormat), fileName, none

    init(_ info: VRInfo?, adding: VRFormat? = nil) {
        guard let info else { self = .checking; return }
        if info.hasEmbedded { self = .embedded(info.entries.count) }
        else if let adding { self = .willAdd(adding) }
        else if !info.filenameTags.isEmpty { self = .fileName }
        else { self = .none }
    }

    @MainActor init(_ model: EditorModel) { self.init(model.vrInfo, adding: model.addVR) }

    var title: String {
        switch self {
        case .checking: return "Checking…"
        case .embedded: return "Headset ready"
        case .willAdd: return "Added on export"
        case .fileName: return "Detected by file name"
        case .none: return "No VR metadata"
        }
    }

    var short: String {
        switch self {
        case .checking: return "Checking…"
        case .embedded(let n): return "VR metadata · \(n)"
        case .willAdd(let f): return "Adding \(f.title)"
        case .fileName: return "VR by file name"
        case .none: return "No VR metadata"
        }
    }

    var detail: String {
        switch self {
        case .checking: return "Reading the file's VR metadata."
        case .embedded: return "Players detect the format automatically. CutVR keeps every entry 1:1 on export."
        case .willAdd(let f): return "The file has no VR metadata. Export writes \(f.title) metadata (st3d/sv3d) into the file and suggests a name ending in \(f.nameTag), so headsets detect it automatically."
        case .fileName: return "No embedded metadata, but players that read file names (DeoVR, HereSphere, Skybox) detect it. Choose the format below to write it into the file too."
        case .none: return "Headsets will show it flat. Choose the format below and CutVR writes it into the exported file."
        }
    }

    var icon: String {
        switch self {
        case .checking: return "hourglass"
        case .embedded: return "checkmark.seal.fill"
        case .willAdd: return "plus.circle.fill"
        case .fileName: return "textformat"
        case .none: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .checking: return Theme.text2
        case .embedded: return Theme.ok
        case .willAdd: return Theme.accent
        case .fileName: return Theme.warn
        case .none: return .orange
        }
    }
}

/// Video and VR parameters relevant for headset playback, drawn over the preview.
struct HeadsetOverlay: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("Resolution", Describe.resolution(model))
            row("Frame rate", Describe.frameRate(model))
            row("Codec", Describe.codec(model.codec))
            row("Bitrate", Describe.bitrate(model))
            row("Layout", Describe.layout(model))
            row("Projection", Describe.projection(model))
            row("Name tags", Describe.nameTags(model))
            row("Headset", HeadsetStatus(model).title)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).foregroundStyle(Theme.text2).frame(width: 76, alignment: .leading)
            Text(v).foregroundStyle(.white)
        }
    }
}

/// Stereo frame packing, used to show a single eye.
enum StereoLayout {
    case sideBySide, topBottom

    /// From embedded metadata, then file name tags, then frame shape.
    static func detect(_ info: VRInfo?, size: CGSize) -> StereoLayout? {
        if let mode = info?.stereoMode?.lowercased() {
            if mode.contains("top") || mode.contains("bottom") || mode.contains("over") { return .topBottom }
            if mode.contains("side") || mode.contains("left") || mode.contains("right") { return .sideBySide }
            if mode.contains("mono") { return nil }
        }
        let tags = Set(info?.filenameTags ?? [])
        if !tags.isDisjoint(with: ["tb", "bt", "ou", "3dv"]) { return .topBottom }
        if !tags.isDisjoint(with: ["sbs", "lr", "rl", "3dh"]) { return .sideBySide }
        guard size.height > 0 else { return nil }
        let ratio = size.width / size.height
        if ratio > 1.8 && ratio < 2.2 { return .sideBySide }
        if ratio > 0.45 && ratio < 0.55 { return .topBottom }
        return nil   // 1:1 is ambiguous (mono 360 or top-bottom 180)
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    var singleEye: StereoLayout? = nil   // nil: whole frame

    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player
        return v
    }
    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        if nsView.singleEye != singleEye {
            nsView.singleEye = singleEye
            nsView.needsLayout = true
        }
    }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    var singleEye: StereoLayout?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Single eye: the player layer is twice as large and the view clips it to the left / upper half.
        // Layer coordinates have their origin at the bottom left, so the upper half needs a negative y offset.
        switch singleEye {
        case .sideBySide: playerLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * 2, height: bounds.height)
        case .topBottom: playerLayer.frame = CGRect(x: 0, y: -bounds.height, width: bounds.width, height: bounds.height * 2)
        case nil: playerLayer.frame = bounds
        }
        CATransaction.commit()
    }
}
