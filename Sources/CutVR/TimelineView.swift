import SwiftUI

/// The edit: a time ruler over the clips laid out one after another. Select tool selects/scrubs, scissors tool cuts.
struct TimelineView: View {
    @EnvironmentObject var model: EditorModel
    @State private var hoverX: CGFloat?
    private let rulerHeight: CGFloat = 20
    private let trackHeight: CGFloat = 64
    private var height: CGFloat { rulerHeight + trackHeight }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = model.editDuration
            let scale = total > 0 ? w / total : 0
            let offsets = model.clipOffsets
            let time = { (px: CGFloat) -> Double in scale > 0 ? min(max(0, Double(px / scale)), total) : 0 }

            ZStack(alignment: .topLeading) {
                ruler(total: total, scale: scale)

                Group {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.bg)
                    thumbnails(scale: scale, offsets: offsets)

                    // clip frames, selection and numbers
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, clip in
                        let selected = model.selectedClip == clip.id
                        let cw = max(2, clip.length * scale - 3)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Theme.accent.opacity(0.2) : .clear)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.18), lineWidth: selected ? 2.5 : 1)
                            if cw > 26 {
                                Text("\(i + 1)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundStyle(selected ? .white : Color.white.opacity(0.85))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(selected ? Theme.accent : Color.black.opacity(0.6)))
                                    .padding(5)
                            }
                        }
                        .frame(width: cw, height: trackHeight)
                        .offset(x: offsets[i] * scale + 1.5)
                    }

                    // scissors preview line
                    if model.tool == .blade, let hx = hoverX {
                        Rectangle().fill(Theme.blade).frame(width: 2, height: trackHeight)
                            .offset(x: hx - 1)
                        Image(systemName: "scissors")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.blade))
                            .offset(x: hx - 11, y: trackHeight / 2 - 11)
                    }
                }
                .frame(height: trackHeight)
                .offset(y: rulerHeight)
                .allowsHitTesting(false)

                playhead(x: model.current * scale)
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

    /// Edit-time ticks with labels, at least ~80 px apart.
    private func ruler(total: Double, scale: Double) -> some View {
        Canvas { ctx, size in
            guard total > 0, scale > 0 else { return }
            let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
            let step = steps.first { $0 * scale >= 80 } ?? 7200
            let minor = step / 5
            var t = 0.0
            while t <= total + 0.0001 {
                let x = t * scale
                let major = abs((t / step).rounded() - t / step) < 0.001
                let h: CGFloat = major ? 7 : 3
                ctx.fill(Path(CGRect(x: x, y: size.height - h, width: 1, height: h)),
                         with: .color(Color.white.opacity(major ? 0.3 : 0.15)))
                if major && x + 40 < size.width {
                    ctx.draw(Text(Self.rulerLabel(t, total: total))
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundColor(Theme.text3),
                             at: CGPoint(x: x + 4, y: 1), anchor: .topLeading)
                }
                t += minor
            }
        }
        .frame(height: rulerHeight)
        .allowsHitTesting(false)
    }

    private static func rulerLabel(_ t: Double, total: Double) -> String {
        let s = Int(t.rounded())
        if total >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        if t != t.rounded() { return String(format: "%d:%04.1f", s / 60, t.truncatingRemainder(dividingBy: 60)) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func playhead(x: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.white).frame(width: 2, height: height - 4).offset(y: 4)
            PlayheadHead().fill(Color.white).frame(width: 12, height: 12)
        }
        .frame(width: 12, height: height, alignment: .top)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .offset(x: x - 6)
        .allowsHitTesting(false)
    }

    /// Each clip shows thumbnails of its own source range.
    private func thumbnails(scale: Double, offsets: [Double]) -> some View {
        let thumbs = model.thumbnails.sorted { $0.time < $1.time }
        let aspect = model.videoSize.height > 0 ? min(2.2, model.videoSize.width / model.videoSize.height) : 16 / 9
        let clips = model.clips
        return Canvas { ctx, size in
            guard scale > 0 else { return }
            let tw = size.height * aspect
            for (i, clip) in clips.enumerated() {
                let x0 = offsets[i] * scale, cw = clip.length * scale
                let rect = CGRect(x: x0 + 1.5, y: 0, width: max(0, cw - 3), height: size.height)
                ctx.drawLayer { layer in
                    layer.clip(to: Path(roundedRect: rect, cornerRadius: 6))
                    layer.fill(Path(rect), with: .color(Theme.track))
                    guard !thumbs.isEmpty else { return }
                    var x = x0
                    while x < x0 + cw {
                        let t = clip.start + (x + tw / 2 - x0) / scale
                        layer.draw(Image(decorative: nearest(thumbs, t), scale: 1),
                                   in: CGRect(x: x, y: 0, width: tw, height: size.height))
                        x += tw
                    }
                }
            }
        }
        .opacity(0.8)
        .frame(height: trackHeight)
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

/// Pointed handle on top of the playhead line.
private struct PlayheadHead: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 2), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 2))
        p.addQuadCurve(to: CGPoint(x: r.minX + 2, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        return p
    }
}
