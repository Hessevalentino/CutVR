import AppKit

/// Self-update from GitHub Releases. Every push to main publishes a release (see .github/workflows/release.yml)
/// tagged v<version> with CutVR.zip; the app compares that version with its own and swaps itself in place.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "Hessevalentino/CutVR"

    struct Release {
        let version: String
        let notes: String
        let zipURL: URL
        let pageURL: URL
    }

    enum Failure: Error, CustomStringConvertible {
        case http(Int), noAsset, badArchive, badSignature, notInBundle
        var description: String {
            switch self {
            case .http(let code): return code == 404 ? "No release has been published yet." : "GitHub returned HTTP \(code)."
            case .noAsset: return "The latest release has no CutVR.zip."
            case .badArchive: return "The downloaded archive does not contain CutVR.app."
            case .badSignature: return "The downloaded app failed the code signature check."
            case .notInBundle: return "CutVR is not running from an app bundle."
            }
        }
    }

    @Published var available: Release?
    @Published var isInstalling = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func checkOnLaunch() {
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        do {
            let release = try await fetchLatest()
            if Self.isNewer(release.version, than: currentVersion) {
                available = release
                if userInitiated { promptInstall() }
            } else {
                available = nil
                if userInitiated { info("You're up to date", "CutVR \(currentVersion) is the latest version.") }
            }
        } catch {
            if userInitiated { info("Cannot check for updates", "\(error)") }
        }
    }

    private func fetchLatest() async throws -> Release {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }

        struct API: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let body: String?
            let html_url: URL
            let assets: [Asset]
        }
        let api = try JSONDecoder().decode(API.self, from: data)
        guard let zip = api.assets.first(where: { $0.name == "CutVR.zip" }) else { throw Failure.noAsset }
        let version = api.tag_name.hasPrefix("v") ? String(api.tag_name.dropFirst()) : api.tag_name
        return Release(version: version, notes: api.body ?? "", zipURL: zip.browser_download_url, pageURL: api.html_url)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Install

    func promptInstall() {
        guard let release = available else { return }
        let alert = NSAlert()
        alert.messageText = "CutVR \(release.version) is available"
        let notes = release.notes.count > 900 ? String(release.notes.prefix(900)) + "…" : release.notes
        alert.informativeText = "You have \(currentVersion).\n\n\(notes)"
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Page")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await install(release) }
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    private func install(_ release: Release) async {
        isInstalling = true
        defer { isInstalling = false }
        do {
            let fm = FileManager.default
            let current = Bundle.main.bundleURL
            guard current.pathExtension == "app" else { throw Failure.notInBundle }

            let work = fm.temporaryDirectory.appendingPathComponent("CutVR-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (downloaded, resp) = try await URLSession.shared.download(from: release.zipURL)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Failure.http(status) }
            let zip = work.appendingPathComponent("CutVR.zip")
            try fm.moveItem(at: downloaded, to: zip)

            let unzip = try await runProcess("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("CutVR.app")
            guard unzip.status == 0, Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier
            else { throw Failure.badArchive }
            let verify = try await runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            guard verify.status == 0 else { throw Failure.badSignature }

            _ = try fm.replaceItemAt(current, withItemAt: newApp)
            relaunch(current)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Update failed"
            alert.informativeText = "\(error)\n\nYou can download the new version from the release page."
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
        }
    }

    /// Starts the new app after this one has quit.
    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func info(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
