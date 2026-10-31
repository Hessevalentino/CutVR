import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// A piece of the source video. The edit is the clips played one after another.
struct Clip: Identifiable, Equatable {
    let id = UUID()
    var start: Double   // source time; always on a keyframe so stream copy can start there
    var end: Double
    var length: Double { end - start }
}

enum EditTool {
    case select, blade
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var url: URL?
    @Published var duration: Double = 0        // source duration
    @Published var current: Double = 0         // playhead in edit time
    @Published var isPlaying = false
    @Published var vrInfo: VRInfo?
    @Published var thumbnails: [(time: Double, image: CGImage)] = []
    @Published var videoSize: CGSize = .zero
    @Published var frameRate: Double = 30
    @Published var codec = ""
    @Published var bitrate: Double = 0          // bits per second

    @Published var clips: [Clip] = []
    @Published var selectedClip: Clip.ID?
    @Published var tool: EditTool = .select
    private var history: [[Clip]] = []

    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatus = ""
    @Published var report: ExportReport?
    @Published var error: String?

    let player = AVPlayer()
    private var asset: AVURLAsset?
    private var videoTrack: AVAssetTrack?
    private var timeObserver: Any?
    private var isSeeking = false
    private var pendingSeek: (Double, Bool)?
    private var exportProcess: Process?
    private var playingClip = 0
    var isScrubbing = false

    var editDuration: Double { clips.reduce(0) { $0 + $1.length } }
    var canUndo: Bool { !history.isEmpty }

    /// Edit-time position where each clip begins.
    var clipOffsets: [Double] {
        var t = 0.0
        return clips.map { c in defer { t += c.length }; return t }
    }

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking, !self.isScrubbing, t.seconds.isFinite else { return }
                self.playerTimeChanged(t.seconds)
            }
        }
    }

    /// Maps the player's source time to edit time and jumps over removed material while playing.
    private func playerTimeChanged(_ source: Double) {
        isPlaying = player.rate != 0
        guard clips.indices.contains(playingClip) else { return }
        let clip = clips[playingClip]
        if isPlaying && source >= clip.end - 0.5 / frameRate {
            if playingClip + 1 < clips.count {
                playingClip += 1
                seekSource(clips[playingClip].start, precise: true)
                current = clipOffsets[playingClip]
            } else {
                player.pause()
                isPlaying = false
                current = editDuration
            }
            return
        }
        current = clipOffsets[playingClip] + min(max(0, source - clip.start), clip.length)
    }

    func open(_ url: URL) async {
        player.pause()
        isPlaying = false
        report = nil
        error = nil
        thumbnails = []
        vrInfo = nil

        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                error = "The file has no video track."
                return
            }
            self.asset = asset
            self.videoTrack = track
            self.url = url
            self.duration = duration
            self.videoSize = try await track.load(.naturalSize)
            let fps = Double(try await track.load(.nominalFrameRate))
            self.frameRate = fps > 0 ? fps : 30
            self.bitrate = Double(try await track.load(.estimatedDataRate))
            if let fd = try await track.load(.formatDescriptions).first {
                let sub = CMFormatDescriptionGetMediaSubType(fd)
                self.codec = String(bytes: [24, 16, 8, 0].map { UInt8((sub >> $0) & 0xff) }, encoding: .ascii) ?? ""
            }
            clips = [Clip(start: 0, end: duration)]
            history = []
            selectedClip = nil
            playingClip = 0
            current = 0
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        } catch {
            self.error = "Cannot open video: \(error.localizedDescription)"
            return
        }

        Task { self.vrInfo = await VRInfo.probe(url) }
        Task { await loadThumbnails(asset: asset) }
    }

    private func loadThumbnails(asset: AVURLAsset) async {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.maximumSize = CGSize(width: 160, height: 90)
        let count = 80
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [(Double, CGImage)] = []
        for await result in gen.images(for: times) {
            guard self.asset === asset else { return }
            if let img = try? result.image {
                images.append((result.requestedTime.seconds, img))
                if images.count % 10 == 0 || images.count == count { thumbnails = images }
            }
        }
        thumbnails = images
    }

    // MARK: Time mapping

    /// Clip index and source time for an edit-time position.
    func locate(_ editTime: Double) -> (index: Int, source: Double)? {
        guard !clips.isEmpty else { return nil }
        let offsets = clipOffsets
        for i in clips.indices.reversed() where editTime >= offsets[i] - 0.000_1 {
            return (i, clips[i].start + min(editTime - offsets[i], clips[i].length))
        }
        return (0, clips[0].start)
    }

    // MARK: Playback

    func togglePlay() {
        if player.rate != 0 {
            player.pause()
            isPlaying = false
        } else {
            if current >= editDuration - 0.05 { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    /// Seeks to an edit-time position.
    func seek(to t: Double, precise: Bool = true) {
        let t = min(max(0, t), editDuration)
        current = t
        guard let (i, source) = locate(t) else { return }
        playingClip = i
        seekSource(source, precise: precise)
    }

    /// Coalescing seek: while a seek is running, only the latest target is kept.
    private func seekSource(_ t: Double, precise: Bool) {
        if isSeeking { pendingSeek = (t, precise); return }
        isSeeking = true
        let tol = precise ? CMTime.zero : CMTime(seconds: 0.4, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: t, preferredTimescale: 60000), toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false
                if let (pt, pp) = self.pendingSeek {
                    self.pendingSeek = nil
                    self.seekSource(pt, precise: pp)
                }
            }
        }
    }

    func step(frames: Int) {
        player.pause()
        isPlaying = false
        seek(to: current + Double(frames) / frameRate)
    }

    // MARK: Editing

    /// Cuts the clip under the edit-time position. Stream copy can only start a clip on a keyframe,
    /// so the cut moves back to the nearest keyframe; the playhead jumps there to show the real cut.
    func split(at editTime: Double) async {
        guard let (i, source) = locate(editTime) else { return }
        let clip = clips[i]
        let cut = await keyframe(atOrBefore: source)
        let minLen = 1 / frameRate
        guard cut - clip.start >= minLen, clip.end - cut >= minLen else { return }
        pushHistory()
        clips[i].end = cut
        clips.insert(Clip(start: cut, end: clip.end), at: i + 1)
        selectedClip = nil
        player.pause()
        isPlaying = false
        seek(to: clipOffsets[i + 1])
    }

    func splitAtPlayhead() async {
        await split(at: current)
    }

    func select(at editTime: Double) {
        guard let (i, _) = locate(editTime) else { return }
        selectedClip = clips[i].id
    }

    /// Removes the selected clip; the following clips move up to close the gap.
    func deleteSelected() {
        guard let id = selectedClip, let i = clips.firstIndex(where: { $0.id == id }) else { return }
        pushHistory()
        let at = clipOffsets[i]
        clips.remove(at: i)
        selectedClip = nil
        player.pause()
        isPlaying = false
        seek(to: min(at, editDuration))
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        clips = previous
        selectedClip = nil
        seek(to: min(current, editDuration))
    }

    private func pushHistory() {
        history.append(clips)
        if history.count > 200 { history.removeFirst() }
    }

    private func keyframe(atOrBefore t: Double) async -> Double {
        guard let track = videoTrack, (try? await track.load(.canProvideSampleCursors)) == true,
              let cursor = track.makeSampleCursor(presentationTimeStamp: CMTime(seconds: t, preferredTimescale: 60000))
        else { return t }
        // Cursor lands on the sample nearest to t; walk back to a sync sample (GOPs are usually < 10 s).
        if cursor.presentationTimeStamp.seconds > t + 0.0005 { _ = cursor.stepInPresentationOrder(byCount: -1) }
        var steps = 0
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue && steps < 3000 {
            if cursor.stepInDecodeOrder(byCount: -1) == 0 { break }
            steps += 1
        }
        let s = cursor.presentationTimeStamp.seconds
        return s.isFinite ? max(0, s) : t
    }

    // MARK: Export

    func chooseDestinationAndExport() {
        guard let url else { return }
        let segments = clips.map { Exporter.Segment(start: $0.start, end: $0.end) }
        guard !segments.isEmpty else { error = "Nothing is left to export."; return }
        let panel = NSSavePanel()
        panel.directoryURL = url.deletingLastPathComponent()
        // Original name stays at the end so VR tokens (e.g. _180_LR) that players read are kept.
        panel.nameFieldStringValue = "EDIT_" + url.lastPathComponent
        panel.canCreateDirectories = true
        // Output always uses the source container: ffmpeg picks the muxer from the extension,
        // and VR box transfer only works MP4→MP4 / MOV→MOV.
        let ext = url.pathExtension
        if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, var dest = panel.url else { return }
        if dest.pathExtension.lowercased() != ext.lowercased() {
            dest = dest.deletingPathExtension().appendingPathExtension(ext)
        }
        if dest.standardizedFileURL == url.standardizedFileURL {
            error = "Cannot overwrite the source file."
            return
        }
        Task { await export(segments: segments, to: dest) }
    }

    func export(segments: [Exporter.Segment], to dest: URL) async {
        guard let url else { return }
        player.pause()
        isPlaying = false
        isExporting = true
        exportProgress = 0
        report = nil
        let report = await Exporter.export(source: url, segments: segments, dest: dest,
            started: { p in Task { @MainActor in self.exportProcess = p } },
            progress: { value, status in
                Task { @MainActor in
                    self.exportProgress = value
                    self.exportStatus = status
                }
            })
        exportProcess = nil
        isExporting = false
        self.report = report
    }

    func cancelExport() {
        exportProcess?.terminate()
    }

    // MARK: Formatting

    static func timecode(_ t: Double) -> String {
        guard t.isFinite else { return "00:00:00.000" }
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
