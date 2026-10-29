import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: BoardStore
    var onComplete: () -> Void

    @State private var workID: String
    @State private var homeID: String
    @State private var launchAtLogin: Bool
    @State private var saveError: String?

    init(store: BoardStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
        _workID = State(initialValue: store.stations.work.id)
        _homeID = State(initialValue: store.stations.home.id)
        _launchAtLogin = State(initialValue: store.launchAtLogin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 15) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "tram.fill", accessibilityDescription: nil)!)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)
                Text("Set up Bart")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 14) {
                stationPicker("Home station", selection: $homeID)
                stationPicker("Work station", selection: $workID)
                if workID == homeID {
                    Text("Choose two different stations.")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            Divider()

            if let saveError {
                Text(saveError).font(.system(size: 12)).foregroundStyle(.red)
            }

            HStack {
                Toggle("Open Bart at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 13))
                    .fixedSize()
                Spacer()
                startButton
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    @ViewBuilder private var startButton: some View {
        if #available(macOS 26.0, *) {
            Button { finish() } label: {
                Text("Start")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .frame(height: 32)
                    .contentShape(Capsule())
            }
                .buttonStyle(.plain)
                .background(Color.accentColor.opacity(0.86), in: Capsule())
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.5)), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5).allowsHitTesting(false))
                .disabled(workID == homeID)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Start") { finish() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(workID == homeID)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func stationPicker(_ title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 110, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(Station.all) { station in
                    Text(station.name).tag(station.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        guard let work = Station.station(id: workID), let home = Station.station(id: homeID) else { return }
        do {
            try store.setStations(work: work, home: home)
            if launchAtLogin != store.launchAtLogin {
                store.setLogin(launchAtLogin)
                if let loginError = store.loginError {
                    saveError = "Launch at login: \(loginError) Turn it off to continue, or allow Bart in System Settings."
                    return
                }
            }
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
