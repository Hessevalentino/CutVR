import AVFoundation
import UniformTypeIdentifiers

/// Serves a local file to AVFoundation with a few bytes replaced in memory; the file itself is never changed.
/// Used for the preview of HEVC tagged `hev1`, which AVFoundation refuses but plays fine as `hvc1`.
final class PatchedFileLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "cutvr-patched"

    private let fd: Int32
    private let fileSize: UInt64
    private let contentType: String
    private let patches: [(offset: UInt64, bytes: [UInt8])]
    let queue = DispatchQueue(label: "cutvr.patched-loader", qos: .userInitiated, attributes: .concurrent)

    init?(url: URL, patches: [(offset: UInt64, bytes: [UInt8])]) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        var st = stat()
        guard fstat(fd, &st) == 0 else { close(fd); return nil }
        self.fd = fd
        self.fileSize = UInt64(st.st_size)
        self.contentType = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.mpeg4Movie.identifier
        self.patches = patches
    }

    deinit { close(fd) }

    /// An asset that reads `url` through `loader`. Keep the loader alive as long as the asset.
    static func asset(for url: URL, patches: [(offset: UInt64, bytes: [UInt8])]) -> (AVURLAsset, PatchedFileLoader)? {
        guard let loader = PatchedFileLoader(url: url, patches: patches),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = scheme
        guard let patchedURL = comps.url else { return nil }
        let asset = AVURLAsset(url: patchedURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (asset, loader)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let info = request.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = Int64(fileSize)
            info.isByteRangeAccessSupported = true
        }
        guard let data = request.dataRequest else { request.finishLoading(); return true }
        queue.async { self.serve(request, data) }
        return true
    }

    private func serve(_ request: AVAssetResourceLoadingRequest, _ data: AVAssetResourceLoadingDataRequest) {
        let chunk = 4 << 20
        var offset = UInt64(max(0, data.currentOffset))
        let end = data.requestsAllDataToEndOfResource ? fileSize
                                                       : min(fileSize, UInt64(data.requestedOffset) + UInt64(data.requestedLength))
        var buffer = [UInt8](repeating: 0, count: chunk)
        while offset < end {
            if request.isCancelled { return }
            let n = Int(min(UInt64(chunk), end - offset))
            let read = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, n, off_t(offset)) }
            guard read > 0 else { request.finishLoading(with: POSIXError(.EIO)); return }
            for p in patches where p.offset < offset + UInt64(read) && p.offset + UInt64(p.bytes.count) > offset {
                for (k, b) in p.bytes.enumerated() {
                    let at = Int64(p.offset) + Int64(k) - Int64(offset)
                    if at >= 0 && at < read { buffer[Int(at)] = b }
                }
            }
            data.respond(with: Data(buffer[0..<read]))
            offset += UInt64(read)
        }
        request.finishLoading()
    }
}
