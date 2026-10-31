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

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player
        return v
    }
    func updateNSView(_ nsView: PlayerNSView, context: Context) {}
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
