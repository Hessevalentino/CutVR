import Foundation

/// Locates command line tools. Apps started from Finder don't inherit the shell PATH,
/// so Homebrew locations are checked explicitly.
enum Tool {
    static func path(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs a process off the main thread. `onLine` receives stdout line by line (used for ffmpeg progress).
func runProcess(_ exe: String, _ args: [String],
                started: ((Process) -> Void)? = nil,
                onLine: ((String) -> Void)? = nil) async throws -> ProcessResult {
    try await withCheckedThrowingContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let outPipe = Pipe(), errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe
            p.standardInput = FileHandle.nullDevice

            var errData = Data()
            let errLock = NSLock()
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                errLock.lock(); errData.append(d); errLock.unlock()
            }

            do { try p.run() } catch { cont.resume(throwing: error); return }
            started?(p)

            var outData = Data()
            var lineBuf = Data()
            let reader = outPipe.fileHandleForReading
            while true {
                let d = reader.availableData
                if d.isEmpty { break }
                outData.append(d)
                guard let onLine else { continue }
                lineBuf.append(d)
                while let nl = lineBuf.firstIndex(of: 10) {
                    onLine(String(decoding: lineBuf[lineBuf.startIndex..<nl], as: UTF8.self))
                    lineBuf.removeSubrange(lineBuf.startIndex...nl)
                }
            }
            p.waitUntilExit()
            errPipe.fileHandleForReading.readabilityHandler = nil
            let rest = errPipe.fileHandleForReading.readDataToEndOfFile()
            errLock.lock(); errData.append(rest); errLock.unlock()

            cont.resume(returning: ProcessResult(status: p.terminationStatus,
                                                 stdout: String(decoding: outData, as: UTF8.self),
                                                 stderr: String(decoding: errData, as: UTF8.self)))
        }
    }
}

/// VR relevant metadata of a file, as reported by ffprobe (st3d/sv3d side data, mkv stereo_mode)
/// and exiftool (Google Spherical V1 XML, QuickTime stereo/projection tags).
struct VRInfo {
    var entries: [String] = []          // normalized "source: key = value" lines, used for comparison
    var filenameTags: [String] = []
    var stereoMode: String?             // e.g. "side by side", "left-right"
    var projection: String?             // e.g. "equirectangular", "fisheye"

    var hasEmbedded: Bool { !entries.isEmpty }

    static func probe(_ url: URL) async -> VRInfo {
        var info = VRInfo()
        info.filenameTags = filenameVRTags(url.deletingPathExtension().lastPathComponent)

        if let ffprobe = Tool.path("ffprobe"),
           let r = try? await runProcess(ffprobe, ["-v", "error", "-select_streams", "v:0",
                                                   "-show_streams", "-of", "json", url.path]),
           let json = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any],
           let stream = (json["streams"] as? [[String: Any]])?.first {
            for sd in stream["side_data_list"] as? [[String: Any]] ?? [] {
                guard let type = sd["side_data_type"] as? String,
                      type == "Stereo 3D" || type == "Spherical Mapping" else { continue }
                for key in sd.keys.sorted() where key != "side_data_type" {
                    info.entries.append("ffprobe \(type): \(key) = \(sd[key]!)")
                }
                if type == "Stereo 3D" { info.stereoMode = sd["type"] as? String }
                if type == "Spherical Mapping" { info.projection = sd["projection"] as? String }
            }
            if let tags = stream["tags"] as? [String: Any] {
                for (k, v) in tags where k.lowercased().contains("stereo") || k.lowercased().contains("spherical") {
                    info.entries.append("ffprobe tag: \(k) = \(v)")
                }
            }
        }

        if let exiftool = Tool.path("exiftool"),
           let r = try? await runProcess(exiftool, ["-j", "-G1", "-a", "-s", url.path]),
           let arr = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [[String: Any]],
           let tags = arr.first {
            let pattern = try! NSRegularExpression(pattern: "(?i)spherical|stereo|projection|fieldofview|heroeye|baseline|viewpacking|disparity")
            for key in tags.keys.sorted() {
                let range = NSRange(key.startIndex..., in: key)
                guard key.hasPrefix("XMP-GSpherical") || pattern.firstMatch(in: key, range: range) != nil else { continue }
                info.entries.append("exiftool \(key) = \(tags[key]!)")
            }
            if info.stereoMode == nil { info.stereoMode = tags["XMP-GSpherical:StereoMode"].map { "\($0)" } }
            if info.projection == nil { info.projection = tags["XMP-GSpherical:ProjectionType"].map { "\($0)" } }
        }
        return info
    }

    /// Players like DeoVR, HereSphere or Skybox detect VR format from tokens in the file name.
    static func filenameVRTags(_ name: String) -> [String] {
        let known: Set<String> = ["180", "190", "200", "220", "360", "vr", "vr180", "vr360", "sbs", "lr", "rl",
                                  "tb", "bt", "ou", "3dh", "3dv", "fisheye", "fisheye190", "mkx200", "mkx220",
                                  "vrca220", "rf52", "mono", "2d", "3d", "180x180", "360x180", "f180", "screen"]
        let tokens = name.lowercased().split(whereSeparator: { "_-. ".contains($0) }).map(String.init)
        return tokens.filter { known.contains($0) }
    }
}

/// VR format CutVR can write into a file that has no embedded VR metadata.
enum VRFormat: String, CaseIterable, Identifiable {
    case sbs180, tb180, mono180, sbs360, tb360, mono360

    var id: String { rawValue }
    var is180: Bool { [.sbs180, .tb180, .mono180].contains(self) }

    /// st3d stereo_mode: 0 mono, 1 top-bottom, 2 left-right.
    var stereoMode: UInt8 {
        switch self {
        case .sbs180, .sbs360: return 2
        case .tb180, .tb360: return 1
        case .mono180, .mono360: return 0
        }
    }

    var title: String {
        switch self {
        case .sbs180: return "180° side-by-side"
        case .tb180: return "180° top-bottom"
        case .mono180: return "180° mono"
        case .sbs360: return "360° side-by-side"
        case .tb360: return "360° top-bottom"
        case .mono360: return "360° mono"
        }
    }

    /// File name tag that players reading names understand.
    var nameTag: String {
        switch self {
        case .sbs180: return "_180_LR"
        case .tb180: return "_180_TB"
        case .mono180: return "_180"
        case .sbs360: return "_360_LR"
        case .tb360: return "_360_TB"
        case .mono360: return "_360"
        }
    }

    init?(cliName: String) { self.init(rawValue: cliName.lowercased()) }

    /// Best guess from the frame shape: 2:1 is usually 180° side-by-side (two square eyes).
    static func suggested(for size: CGSize) -> VRFormat? {
        guard size.height > 0 else { return nil }
        let r = size.width / size.height
        if r > 1.9 && r < 2.1 { return .sbs180 }
        return nil
    }
}

struct ExportReport {
    var ok: Bool
    var message: String
    var missing: [String] = []
    var outputURL: URL?
}

/// Lossless cut: ffmpeg stream copy + metadata restore + VR metadata verification.
enum Exporter {
    struct Segment {
        var start: Double
        var end: Double
        var length: Double { end - start }
    }

    /// Joins segments that continue exactly where the previous one ends (left over by a cut with nothing
    /// removed). Fewer parts means fewer joins; a single segment skips the temporary parts entirely.
    static func merged(_ segments: [Segment]) -> [Segment] {
        var out: [Segment] = []
        for seg in segments {
            if let last = out.last, abs(seg.start - last.end) < 0.000_001 {
                out[out.count - 1].end = seg.end
            } else {
                out.append(seg)
            }
        }
        return out
    }

    /// True when both URLs point to the same file on disk, also when the paths differ only in letter case
    /// (case-insensitive APFS) or lead through a symlink. A file that does not exist is never the same.
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        func identifier(_ url: URL) -> NSObject? {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            return (try? resolved.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
                .fileResourceIdentifier as? NSObject
        }
        guard let ia = identifier(a), let ib = identifier(b) else { return false }
        return ia.isEqual(ib)
    }

    static func cut(source: URL, start: Double, end: Double, dest: URL,
                    started: ((Process) -> Void)? = nil,
                    progress: ((Double, String) -> Void)? = nil) async -> ExportReport {
        await export(source: source, segments: [Segment(start: start, end: end)], dest: dest,
                     started: started, progress: progress)
    }

    /// Exports `segments` (each starting on a keyframe) one after another into `dest`.
    /// One segment is cut straight to `dest`. Several are cut into temporary parts next to `dest`
    /// and joined with the concat demuxer. (Concat with inpoint/outpoint directly on the source
    /// loses ~1 s of video per join on files interleaved in 1 s chunks.)
    /// `addVR` writes Google Spherical V2 metadata (st3d/sv3d) when the source has no embedded VR metadata.
    static func export(source: URL, segments: [Segment], dest: URL, addVR: VRFormat? = nil,
                       started: ((Process) -> Void)? = nil,
                       progress: ((Double, String) -> Void)? = nil) async -> ExportReport {
        guard let ffmpeg = Tool.path("ffmpeg") else {
            return ExportReport(ok: false, message: "ffmpeg not found (brew install ffmpeg).")
        }
        let segments = merged(segments)
        guard !segments.isEmpty else { return ExportReport(ok: false, message: "Nothing to export.") }
        // ffmpeg runs with -y: writing over the file it reads would destroy the source.
        guard !isSameFile(source, dest) else {
            return ExportReport(ok: false, message: "Cannot overwrite the source file.")
        }
        let ext = dest.pathExtension.lowercased()
        let isMP4Family = ["mp4", "mov", "m4v"].contains(ext)
        let total = segments.reduce(0) { $0 + $1.length }

        var outputArgs = ["-map", "0", "-ignore_unknown", "-c", "copy", "-map_metadata", "0"]
        if isMP4Family {
            // -strict unofficial keeps st3d/sv3d where possible (VRBoxes fixes the rest).
            // No +faststart: moov must stay at the end so VRBoxes can rewrite it without touching mdat.
            outputArgs += ["-strict", "unofficial", "-movflags", "+use_metadata_tags"]
        }

        // Runs ffmpeg, mapping its progress to [base, base + share] of the whole export.
        func ffmpegRun(_ args: [String], length: Double, base: Double, share: Double, status: String) async -> String? {
            progress?(base, status)
            let full = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y"] + args
            do {
                let r = try await runProcess(ffmpeg, full, started: started) { line in
                    if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)), length > 0 {
                        progress?(base + share * min(1, us / 1_000_000 / length), status)
                    }
                }
                if r.status == 0 { return nil }
                return r.status == 15 ? "Cancelled." : "ffmpeg failed: \(r.stderr.suffix(600))"
            } catch {
                return "Cannot start ffmpeg: \(error.localizedDescription)"
            }
        }

        // -ss before -i + stream copy: starts at the keyframe <= start. Segment starts are already keyframes;
        // +1 ms makes sure ffmpeg doesn't fall back to the previous one because of rounding.
        func cutArgs(_ seg: Segment, to url: URL) -> [String] {
            ["-ss", String(format: "%.6f", seg.start + 0.001), "-i", source.path,
             "-t", String(format: "%.6f", seg.length), "-avoid_negative_ts", "make_zero"]
                + outputArgs + ["-progress", "pipe:1", "-nostats", url.path]
        }

        if segments.count == 1 {
            if let err = await ffmpegRun(cutArgs(segments[0], to: dest), length: total, base: 0, share: 1,
                                         status: "Cutting (no re-encode)…") {
                try? FileManager.default.removeItem(at: dest)
                return ExportReport(ok: false, message: err)
            }
        } else {
            let tmp = dest.deletingLastPathComponent().appendingPathComponent(".cutvr-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmp) }
            do {
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            } catch {
                return ExportReport(ok: false, message: "Cannot create temporary folder: \(error.localizedDescription)")
            }
            var parts: [URL] = []
            var done = 0.0
            for (i, seg) in segments.enumerated() {
                let part = tmp.appendingPathComponent("part\(i).\(ext.isEmpty ? "mp4" : ext)")
                if let err = await ffmpegRun(cutArgs(seg, to: part), length: seg.length, base: 0.5 * done / total,
                                             share: 0.5 * seg.length / total,
                                             status: "Cutting part \(i + 1)/\(segments.count)…") {
                    return ExportReport(ok: false, message: err)
                }
                parts.append(part)
                done += seg.length
            }
            let list = tmp.appendingPathComponent("list.txt")
            let listText = parts.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n")
            do { try listText.write(to: list, atomically: true, encoding: .utf8) } catch {
                return ExportReport(ok: false, message: "Cannot write part list: \(error.localizedDescription)")
            }
            let joinArgs = ["-f", "concat", "-safe", "0", "-i", list.path] + outputArgs
                + ["-progress", "pipe:1", "-nostats", dest.path]
            if let err = await ffmpegRun(joinArgs, length: total, base: 0.5, share: 0.5,
                                         status: "Joining \(segments.count) parts…") {
                try? FileManager.default.removeItem(at: dest)
                return ExportReport(ok: false, message: err)
            }
        }

        var notes: [String] = []
        var boxesOK = true
        var added: VRBoxes.TrackVR?
        var addedFormat: VRFormat?
        if isMP4Family {
            // Must run while moov is still at the end of the file (exiftool moves it to the front).
            progress?(1, "Transferring VR boxes…")
            let sourceHasVR = addVR == nil ? true : await VRInfo.probe(source).hasEmbedded
            do {
                if let format = addVR {
                    // Only when the source has nothing of its own; existing metadata always wins.
                    let srcBoxes = try VRBoxes.extract(source)
                    if srcBoxes.allSatisfy(\.isEmpty) && !sourceHasVR {
                        added = VRBoxes.sphericalV2(format)
                        try VRBoxes.write([added!], to: dest)
                        addedFormat = format
                    } else {
                        try VRBoxes.transfer(from: source, to: dest)
                    }
                } else {
                    try VRBoxes.transfer(from: source, to: dest)
                }
            } catch {
                boxesOK = false
                notes.append("Cannot write VR boxes: \(error)")
            }

            // ffmpeg drops QuickTime udta (title, author, thumbnail…) – exiftool copies it back from the source.
            // GSpherical is excluded: the V1 uuid box was already transferred byte-exact.
            if let exiftool = Tool.path("exiftool") {
                progress?(1, "Copying metadata from source…")
                let r = try? await runProcess(exiftool, ["-q", "-q", "-overwrite_original", "-tagsFromFile", source.path,
                                                         "-all:all", "--XMP-GSpherical:all", dest.path])
                if r?.status != 0 { notes.append("exiftool: \(r?.stderr ?? "cannot start")") }
            } else {
                notes.append("exiftool not found – title, author and thumbnail were not copied (brew install exiftool).")
            }

            if boxesOK {
                let expected = try? added.map { [$0] } ?? VRBoxes.extract(source)
                boxesOK = expected != nil && expected == (try? VRBoxes.extract(dest))
                if !boxesOK { notes.append(added == nil ? "VR boxes (st3d/sv3d/vexu/uuid) differ from the source!"
                                                        : "The added VR boxes could not be read back!") }
            }
        }

        progress?(1, "Verifying VR metadata…")
        let src = await VRInfo.probe(source)
        let out = await VRInfo.probe(dest)
        let missing = src.entries.filter { !out.entries.contains($0) }

        var report = ExportReport(ok: missing.isEmpty && boxesOK, message: "", missing: missing, outputURL: dest)
        if let format = addedFormat {
            let readBack = out.hasEmbedded && out.stereoMode != nil && out.projection != nil
            report.ok = boxesOK && readBack
            report.message = report.ok
                ? "Saved. VR metadata added: \(format.title) (\(out.stereoMode!), \(out.projection!)) ✓"
                : "Saved, but the added VR metadata could not be verified!"
        } else if !src.hasEmbedded {
            report.message = "Saved. The source has no embedded VR metadata – the file name was kept."
        } else if report.ok {
            report.message = "Saved. VR metadata preserved 1:1 (\(src.entries.count) entries) ✓"
        } else {
            report.message = missing.isEmpty ? "Saved, but VR metadata do not match!" : "Saved, but \(missing.count) VR metadata entries are missing!"
        }
        if !notes.isEmpty { report.message += "\n" + notes.joined(separator: "\n") }
        return report
    }
}
