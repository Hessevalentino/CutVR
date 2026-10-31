import SwiftUI

@main
struct CutVRApp: App {
    @StateObject private var model = EditorModel()
    @StateObject private var updater = Updater.shared

    init() {
        // Headless mode for scripting/testing: CutVR [--vr <format>] --cut <src> <dest> <start-end> [<start-end> …]
        // Parts (in seconds) are joined in the given order. --vr sbs180|tb180|mono180|sbs360|tb360|mono360
        // writes VR metadata when the source has none.
        var args = CommandLine.arguments
        var addVR: VRFormat?
        if let v = args.firstIndex(of: "--vr"), v + 1 < args.count {
            guard let format = VRFormat(cliName: args[v + 1]) else {
                print("Unknown --vr format. Use one of: " + VRFormat.allCases.map(\.rawValue).joined(separator: ", "))
                exit(2)
            }
            addVR = format
            args.removeSubrange(v...(v + 1))
        }
        if let i = args.firstIndex(of: "--cut"), args.count >= i + 4 {
            let src = URL(fileURLWithPath: args[i + 1]), dest = URL(fileURLWithPath: args[i + 2])
            let segments = args[(i + 3)...].compactMap { arg -> Exporter.Segment? in
                let p = arg.split(separator: "-").compactMap { Double($0) }
                return p.count == 2 ? Exporter.Segment(start: p[0], end: p[1]) : nil
            }
            Task {
                let r = await Exporter.export(source: src, segments: segments, dest: dest, addVR: addVR)
                print(r.message)
                r.missing.forEach { print("missing: \($0)") }
                exit(r.ok ? 0 : 1)
            }
            dispatchMain()
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("CutVR", id: "main") {
            ContentView().environmentObject(model).environmentObject(updater)
                .onAppear { updater.checkOnLaunch() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About CutVR") { showAbout() }
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }
                    .disabled(updater.isInstalling || model.isExporting)
            }
        }
    }

    private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Valentino Hesse\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(
            string: "hesse.works",
            attributes: [.font: NSFont.systemFont(ofSize: 12), .link: URL(string: "https://hesse.works")!]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "CutVR",
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© Valentino Hesse · hesse.works",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
