import SwiftUI
import AVFoundation

/// Video and VR parameters relevant for headset playback, drawn over the preview.
struct HeadsetOverlay: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        let info = model.vrInfo
        VStack(alignment: .leading, spacing: 2) {
            row("Resolution", "\(Int(model.videoSize.width))×\(Int(model.videoSize.height))")
            row("Frame rate", String(format: "%.2f fps", model.frameRate))
            row("Codec", codecName(model.codec))
            row("Bitrate", model.bitrate > 0 ? String(format: "%.1f Mbps", model.bitrate / 1_000_000) : "–")
            row("Layout", layout(info))
            row("Projection", info?.projection ?? "not set")
            row("Name tags", info.map { $0.filenameTags.isEmpty ? "none" : $0.filenameTags.joined(separator: " ") } ?? "…")
            row("Headset", detection(info))
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.65)))
        .allowsHitTesting(false)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).foregroundStyle(Theme.text2).frame(width: 74, alignment: .leading)
            Text(v).foregroundStyle(.white)
        }
    }

    private func codecName(_ fourCC: String) -> String {
        let names = ["avc1": "H.264", "avc3": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "dvh1": "Dolby Vision",
                     "av01": "AV1", "vp09": "VP9", "apcn": "ProRes 422", "apch": "ProRes 422 HQ", "ap4h": "ProRes 4444"]
        guard !fourCC.isEmpty else { return "–" }
        return names[fourCC].map { "\($0) (\(fourCC))" } ?? fourCC
    }

    private func layout(_ info: VRInfo?) -> String {
        if let s = info?.stereoMode { return s }
        // Guess from frame shape when nothing is embedded.
        let ratio = model.videoSize.height > 0 ? model.videoSize.width / model.videoSize.height : 0
        if ratio > 1.8 && ratio < 2.2 { return "side by side? (guess)" }
        if ratio > 0.9 && ratio < 1.1 { return "top-bottom / mono? (guess)" }
        return "unknown"
    }

    private func detection(_ info: VRInfo?) -> String {
        guard let info else { return "…" }
        if info.hasEmbedded { return "auto (embedded metadata)" }
        if !info.filenameTags.isEmpty { return "by file name only" }
        return "manual setting needed"
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
