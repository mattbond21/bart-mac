import AppKit
import SwiftUI
import WidgetKit

@main
enum WidgetPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = CommandLine.arguments.dropFirst().first ?? "/tmp"
        Task { @MainActor in
            let entry = BartEntry(date: Date(), snapshot: WidgetBoardLoader.preview)
            for (name, family, width, height) in [
                ("small", WidgetFamily.systemSmall, 164.0, 164.0),
                ("medium", WidgetFamily.systemMedium, 344.0, 164.0),
                ("large", WidgetFamily.systemLarge, 344.0, 344.0)
            ] {
                for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                    let view = NSHostingView(rootView: BartWidgetView(entry: entry, previewFamily: family)
                        .padding(16).frame(width: width, height: height)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, theme == "dark" ? .dark : .light))
                    view.appearance = NSAppearance(named: appearance)
                    let window = NSWindow(contentRect: NSRect(x: -2000, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = view
                    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
                    window.layoutIfNeeded()
                    try? await Task.sleep(for: .milliseconds(100))
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let data = bitmap.representation(using: .png, properties: [:]) {
                            try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("widget-\(name)-\(theme).png"))
                        }
                    }
                }
            }
            NSApp.terminate(nil)
        }
        app.run()
    }
}
