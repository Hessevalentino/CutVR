import Foundation

/// Byte-exact transfer of VR boxes between MP4/MOV files.
///
/// ffmpeg's mov muxer does not round-trip VR metadata faithfully: in .mov it drops st3d/sv3d,
/// in .mp4 it adds an Apple `vexu` box that overrides st3d for readers, and Google Spherical V1
/// (uuid XML) is always lost. So after the stream copy, the VR boxes of the output's video
/// sample entries are replaced by exact copies of the source's.
///
/// Only the moov box is rewritten. It must be the last top-level box (ffmpeg without +faststart),
/// so mdat and therefore all chunk offsets stay untouched.
enum VRBoxes {
    /// VR boxes inside a visual sample entry (Google st3d/sv3d, Apple vexu/hfov).
    static let entryTypes: Set<String> = ["st3d", "sv3d", "vexu", "hfov"]
    /// Google Spherical Video V1 uuid (XML) inside trak.
    static let sphericalUUID = Data([0xff, 0xcc, 0x82, 0x63, 0xf8, 0x55, 0x4a, 0x93,
                                     0x88, 0x14, 0x58, 0x7a, 0x02, 0x52, 0x1f, 0xdd])

    struct TrackVR: Equatable {
        var entryBoxes: [Data] = []   // complete boxes incl. header
        var trakUUIDs: [Data] = []
        var isEmpty: Bool { entryBoxes.isEmpty && trakUUIDs.isEmpty }
    }

    enum Failure: Error, CustomStringConvertible {
        case noMoov, moovNotLast, malformed(String)
        var description: String {
            switch self {
            case .noMoov: return "file has no moov box"
            case .moovNotLast: return "moov is not at the end of the file"
            case .malformed(let s): return "malformed MP4 structure (\(s))"
            }
        }
    }

    // MARK: Box tree

    /// A box parsed only as deep as needed. `prefix` holds non-box bytes before children
    /// (full box header, stsd entry count, sample entry fields).
    final class Box {
        var type: String
        var prefix = Data()
        var payload = Data()      // opaque content when `children` is nil
        var children: [Box]?

        init(type: String) { self.type = type }

        func serialized() -> Data {
            var body = prefix
            if let children { for c in children { body.append(c.serialized()) } } else { body.append(payload) }
            var out = Data()
            if body.count + 8 <= UInt32.max {
                out.append(be32(UInt32(body.count + 8)))
                out.append(contentsOf: Array(type.utf8))
            } else {
                out.append(be32(1))
                out.append(contentsOf: Array(type.utf8))
                out.append(be64(UInt64(body.count + 16)))
            }
            out.append(body)
            return out
        }

        func child(_ t: String) -> Box? { children?.first { $0.type == t } }
    }

    /// Parses boxes in `data[range]` (data must start at index 0). `container` returns the prefix length
    /// for boxes to descend into, nil for opaque ones.
    static func parse(_ data: Data, _ range: Range<Int>, container: (Box, Box?) -> Int?, parent: Box?) throws -> [Box] {
        var boxes: [Box] = []
        var i = range.lowerBound
        while i + 8 <= range.upperBound {
            var size = Int(readBE32(data, i))
            let type = String(decoding: data[(i + 4)..<(i + 8)], as: UTF8.self)
            var header = 8
            if size == 1 {
                guard i + 16 <= range.upperBound else { throw Failure.malformed(type) }
                size = Int(readBE64(data, i + 8)); header = 16
            } else if size == 0 {
                size = range.upperBound - i
            }
            guard size >= header, i + size <= range.upperBound else { throw Failure.malformed(type) }
            let box = Box(type: type)
            let bodyStart = i + header, end = i + size
            if let prefixLen = container(box, parent), bodyStart + prefixLen <= end {
                box.prefix = data[bodyStart..<(bodyStart + prefixLen)]
                box.children = try parse(data, (bodyStart + prefixLen)..<end, container: container, parent: box)
            } else {
                box.payload = data[bodyStart..<end]
            }
            boxes.append(box)
            i = end
        }
        return boxes
    }

    /// Which boxes to descend into, and how many prefix bytes they have.
    private static func containerPrefix(_ box: Box, _ parent: Box?) -> Int? {
        switch box.type {
        case "moov", "trak", "mdia", "minf", "stbl": return 0
        case "stsd": return 8                           // version/flags + entry_count
        default:
            // Visual sample entries: 8 bytes SampleEntry + 70 bytes VisualSampleEntry fields.
            if parent?.type == "stsd", isVisualEntry(box.type) { return 78 }
            return nil
        }
    }

    private static func isVisualEntry(_ t: String) -> Bool {
        ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "vp09", "vp08", "mp4v",
         "apcn", "apch", "apcs", "apco", "ap4h", "ap4x", "jpeg", "mjpa", "encv"].contains(t)
    }

    private static func isVideoTrak(_ trak: Box) -> Bool {
        guard let hdlr = trak.child("mdia")?.children?.first(where: { $0.type == "hdlr" }) else { return false }
        // hdlr payload: version/flags(4) pre_defined(4) handler_type(4)
        let p = hdlr.payload
        guard p.count >= 12 else { return false }
        return String(decoding: p[(p.startIndex + 8)..<(p.startIndex + 12)], as: UTF8.self) == "vide"
    }

    private static func sampleEntries(_ trak: Box) -> [Box] {
        trak.child("mdia")?.child("minf")?.child("stbl")?.child("stsd")?.children?
            .filter { $0.children != nil } ?? []
    }

    // MARK: File access

    /// Returns moov offset, its full bytes, and whether it is the last top-level box.
    private static func readMoov(_ url: URL) throws -> (offset: UInt64, data: Data, isLast: Bool) {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let fileSize = try fh.seekToEnd()
        var pos: UInt64 = 0
        var found: (UInt64, UInt64)?
        while pos + 8 <= fileSize {
            try fh.seek(toOffset: pos)
            guard let h = try fh.read(upToCount: 16), h.count >= 8 else { break }
            var size = UInt64(readBE32(h, 0))
            if size == 1, h.count >= 16 { size = readBE64(h, 8) } else if size == 0 { size = fileSize - pos }
            guard size >= 8 else { throw Failure.malformed("top-level") }
            if String(decoding: h[4..<8], as: UTF8.self) == "moov" { found = (pos, size) }
            pos += size
        }
        guard let (off, size) = found else { throw Failure.noMoov }
        try fh.seek(toOffset: off)
        guard let data = try fh.read(upToCount: Int(size)), data.count == Int(size) else { throw Failure.malformed("moov") }
        return (off, data, off + size == fileSize)
    }

    private static func parseMoov(_ data: Data) throws -> Box {
        guard let moov = try parse(data, 0..<data.count, container: containerPrefix, parent: nil).first,
              moov.type == "moov" else { throw Failure.noMoov }
        return moov
    }

    /// VR boxes of every video track, in track order.
    static func extract(_ url: URL) throws -> [TrackVR] {
        let moov = try parseMoov(try readMoov(url).data)
        return (moov.children ?? []).filter { $0.type == "trak" && isVideoTrak($0) }.map { trak in
            var vr = TrackVR()
            if let entry = sampleEntries(trak).first {
                vr.entryBoxes = entry.children!.filter { entryTypes.contains($0.type) }.map { $0.serialized() }
            }
            vr.trakUUIDs = trak.children!.filter(isSphericalUUID).map { $0.serialized() }
            return vr
        }
    }

    /// Makes the VR boxes of `dest` exactly match `source`. Returns true if the file was changed.
    @discardableResult
    static func transfer(from source: URL, to dest: URL) throws -> Bool {
        let src = try extract(source)
        let (offset, data, isLast) = try readMoov(dest)
        let moov = try parseMoov(data)
        let videoTraks = (moov.children ?? []).filter { $0.type == "trak" && isVideoTrak($0) }

        var changed = false
        for (idx, trak) in videoTraks.enumerated() {
            let want = idx < src.count ? src[idx] : TrackVR()
            for entry in sampleEntries(trak) {
                let current = entry.children!.filter { entryTypes.contains($0.type) }.map { $0.serialized() }
                guard current != want.entryBoxes else { continue }
                entry.children!.removeAll { entryTypes.contains($0.type) }
                entry.children! += try want.entryBoxes.flatMap { try parse($0, 0..<$0.count, container: { _, _ in nil }, parent: nil) }
                changed = true
            }
            let currentUUIDs = trak.children!.filter(isSphericalUUID).map { $0.serialized() }
            if currentUUIDs != want.trakUUIDs {
                trak.children!.removeAll(where: isSphericalUUID)
                trak.children! += try want.trakUUIDs.flatMap { try parse($0, 0..<$0.count, container: { _, _ in nil }, parent: nil) }
                changed = true
            }
        }
        guard changed else { return false }
        guard isLast else { throw Failure.moovNotLast }

        let newMoov = moov.serialized()
        let fh = try FileHandle(forWritingTo: dest)
        defer { try? fh.close() }
        try fh.truncate(atOffset: offset)
        try fh.seek(toOffset: offset)
        try fh.write(contentsOf: newMoov)
        return true
    }

    /// Absolute file offsets of the type field of every `hev1` sample entry.
    /// AVFoundation cannot decode `hev1`, but plays the same stream when the entry is called `hvc1`.
    static func hev1EntryOffsets(_ url: URL) throws -> [UInt64] {
        let (moovOffset, data, _) = try readMoov(url)
        var found: [UInt64] = []
        // Walks boxes in data[range]; offsets are relative to data.
        func walk(_ range: Range<Int>, path: [String]) {
            var i = range.lowerBound
            while i + 8 <= range.upperBound {
                var size = Int(readBE32(data, i)), header = 8
                if size == 1, i + 16 <= range.upperBound { size = Int(readBE64(data, i + 8)); header = 16 }
                else if size == 0 { size = range.upperBound - i }
                guard size >= header, i + size <= range.upperBound else { return }
                let type = String(decoding: data[(i + 4)..<(i + 8)], as: UTF8.self)
                if path.last == "stsd" {
                    if type == "hev1" { found.append(moovOffset + UInt64(i + 4)) }
                } else if let prefix = ["moov": 0, "trak": 0, "mdia": 0, "minf": 0, "stbl": 0, "stsd": 8][type] {
                    walk((i + header + prefix)..<(i + size), path: path + [type])
                }
                i += size
            }
        }
        walk(0..<data.count, path: [])
        return found
    }

    private static func isSphericalUUID(_ box: Box) -> Bool {
        box.type == "uuid" && box.payload.count >= 16 && box.payload.prefix(16) == sphericalUUID
    }
}

// MARK: Big-endian helpers

private func readBE32(_ d: Data, _ i: Int) -> UInt32 {
    let s = d.startIndex + i
    return d[s..<(s + 4)].reduce(0) { $0 << 8 | UInt32($1) }
}

private func readBE64(_ d: Data, _ i: Int) -> UInt64 {
    let s = d.startIndex + i
    return d[s..<(s + 8)].reduce(0) { $0 << 8 | UInt64($1) }
}

private func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
private func be64(_ v: UInt64) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
