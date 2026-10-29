import AppKit
import Combine
import Sparkle
import SwiftUI

@main
enum BartApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = BoardStore()
    private let boardSize = NSSize(width: 420, height: 465)
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            let image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Bart")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
            button.target = self; button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = boardSize
        popover.contentViewController = NSHostingController(rootView: BoardView(store: store, openSettings: { [weak self] in self?.showSettings() }, checkForUpdates: { [weak self] in self?.checkForUpdates() }))
        subscription = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh(force: true) }
        }
        updateStatus()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 {
            let path = arguments[index + 1]
            Task {
                await store.refresh(force: true)
                await snapshot(path: path)
                NSApp.terminate(nil)
            }
        } else if arguments.contains("--diagnose") {
            Task {
                await store.refresh(force: true)
                print("Feed: \(store.feedTime.map { Pacific.format($0, "yyyy-MM-dd h:mm:ss a") } ?? "unavailable")")
                for train in store.liveTrains {
                    print("Live \(train.id): \(store.journey.origin.name) arrival \(Pacific.format(train.boardingTime, "h:mm:ss a")), departs \(Pacific.format(train.departure, "h:mm:ss a")), \(store.journey.destination.name) \(Pacific.format(train.destinationArrival, "h:mm:ss a")); delay \(train.boardingDelay ?? 0)s")
                }
                print("Next three trains: \(store.upcomingTrains.count)")
                for train in store.upcomingTrains { print("\(train.isLive ? "Live" : "Scheduled"): \(Pacific.format(train.boardingTime, "h:mm a")) → \(Pacific.format(train.destinationArrival, "h:mm a"))") }
                print("Widget cache: \(SharedBoardCache.snapshot?.trains.count ?? 0) trains; group \(SharedBoardCache.groupIdentifier)")
                if let error = store.widgetError { print("WIDGET ERROR: \(error)") }
                if let error = store.error { print("ERROR: \(error)") }
                if let error = store.scheduleError { print("ERROR: \(error)") }
                NSApp.terminate(nil)
            }
        } else {
            store.start()
            let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            let updated = UserDefaults.standard.string(forKey: "lastSeenVersion") != version
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            UserDefaults.standard.set(version, forKey: "lastSeenVersion")
            if arguments.contains("--show") || firstLaunch || updated { togglePopover() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return false
    }

    private func updateStatus() {
        status.button?.toolTip = "\(store.menuTitle)\n\(store.journey.origin.name) → \(store.journey.destination.name) · \(store.menuIsLive ? "Live prediction" : "Scheduled departure")"
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit Bart", action: #selector(quit), keyEquivalent: "q").target = self
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else if let button = status.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Task { await store.refresh() }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func checkForUpdates() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates(nil)
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 585), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Bart Settings"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(store: store))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "bartmac" }), !popover.isShown { togglePopover() }
    }

    private func snapshot(path: String) async {
        let isSettings = CommandLine.arguments.contains("--snapshot-settings")
        let content = isSettings ? AnyView(SettingsView(store: store)) : AnyView(BoardView(store: store))
        let view = NSHostingView(rootView: content)
        if CommandLine.arguments.contains("--dark") { view.appearance = NSAppearance(named: .darkAqua) }
        let size = isSettings ? NSSize(width: 480, height: 585) : boardSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -2000, y: 0), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        view.frame = NSRect(origin: .zero, size: size)
        try? await Task.sleep(for: .milliseconds(300))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            do { try data.write(to: URL(fileURLWithPath: path)); print("Saved \(path)") }
            catch { print("Snapshot failed: \(error.localizedDescription)") }
        }
    }
}
