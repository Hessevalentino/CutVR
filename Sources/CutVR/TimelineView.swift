import SwiftUI

/// The edit: clips laid out one after another. Select tool selects/scrubs, scissors tool cuts.
struct TimelineView: View {
    @EnvironmentObject var model: EditorModel
    @State private var hoverX: CGFloat?
    private let height: CGFloat = 72

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = model.editDuration
            let scale = total > 0 ? w / total : 0
            let offsets = model.clipOffsets
            let time = { (px: CGFloat) -> Double in scale > 0 ? min(max(0, Double(px / scale)), total) : 0 }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.panel)

                thumbnails(scale: scale, offsets: offsets)

                // clip frames, selection and numbers
                ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, clip in
                    let selected = model.selectedClip == clip.id
                    let cw = max(2, clip.length * scale - 2)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selected ? Theme.accent.opacity(0.22) : .clear)
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.25), lineWidth: selected ? 3 : 1)
                        if cw > 26 {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                .padding(4)
                        }
                    }
                    .frame(width: cw, height: height)
                    .offset(x: offsets[i] * scale + 1)
                    .allowsHitTesting(false)
                }

                // scissors preview line
                if model.tool == .blade, let hx = hoverX {
                    Rectangle().fill(Theme.blade).frame(width: 2, height: height)
                        .offset(x: hx - 1)
                        .allowsHitTesting(false)
                    Image(systemName: "scissors")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.blade)
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                        .offset(x: hx - 11, y: height / 2 - 11)
                        .allowsHitTesting(false)
                }

                // playhead
                Rectangle().fill(Color.white).frame(width: 2, height: height)
                    .offset(x: model.current * scale - 1)
                    .allowsHitTesting(false)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended: hoverX = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard model.tool == .select else { hoverX = g.location.x; return }
                    model.isScrubbing = true
                    model.seek(to: time(g.location.x), precise: false)
                }
                .onEnded { g in
                    let t = time(g.location.x)
                    if model.tool == .blade {
                        Task { await model.split(at: t) }
                    } else {
                        model.seek(to: t)
                        if abs(g.translation.width) < 3 { model.select(at: t) }
                        model.isScrubbing = false
                    }
                })
        }
        .frame(height: height)
        .disabled(model.isExporting)
    }

    /// Each clip shows thumbnails of its own source range.
    private func thumbnails(scale: Double, offsets: [Double]) -> some View {
        let thumbs = model.thumbnails.sorted { $0.time < $1.time }
        let aspect = model.videoSize.height > 0 ? min(2.2, model.videoSize.width / model.videoSize.height) : 16 / 9
        let clips = model.clips
        return Canvas { ctx, size in
            guard !thumbs.isEmpty, scale > 0 else { return }
            let tw = size.height * aspect
            for (i, clip) in clips.enumerated() {
                let x0 = offsets[i] * scale, cw = clip.length * scale
                let rect = CGRect(x: x0 + 1, y: 0, width: max(0, cw - 2), height: size.height)
                ctx.drawLayer { layer in
                    layer.clip(to: Path(roundedRect: rect, cornerRadius: 5))
                    layer.fill(Path(rect), with: .color(Theme.track))
                    var x = x0
                    while x < x0 + cw {
                        let t = clip.start + (x + tw / 2 - x0) / scale
                        let img = nearest(thumbs, t)
                        layer.draw(Image(decorative: img, scale: 1),
                                   in: CGRect(x: x, y: 0, width: tw, height: size.height))
                        x += tw
                    }
                }
            }
        }
        .opacity(0.75)
        .frame(height: height)
        .allowsHitTesting(false)
    }

    private func nearest(_ thumbs: [(time: Double, image: CGImage)], _ t: Double) -> CGImage {
        var lo = 0, hi = thumbs.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if thumbs[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0 && abs(thumbs[lo - 1].time - t) < abs(thumbs[lo].time - t) { lo -= 1 }
        return thumbs[lo].image
    }
}
