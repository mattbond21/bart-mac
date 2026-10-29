import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: BoardStore
    @State private var workID: String
    @State private var homeID: String
    @State private var saveError: String?
    @State private var saved = false

    init(store: BoardStore) {
        self.store = store
        _workID = State(initialValue: store.stations.work.id)
        _homeID = State(initialValue: store.stations.home.id)
    }

    var body: some View {
        Form {
            Section("Commute stations") {
                Picker("Work", selection: $workID) {
                    ForEach(Station.all) { Text($0.name).tag($0.id) }
                }
                Picker("Home", selection: $homeID) {
                    ForEach(Station.all) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Button("Swap Work and Home", systemImage: "arrow.up.arrow.down") {
                        (workID, homeID) = (homeID, workID); saved = false
                    }
                    Spacer()
                    Button(saved ? "Saved" : "Save stations") { saveStations() }
                        .buttonStyle(.borderedProminent).disabled(workID == homeID)
                        .keyboardShortcut(.defaultAction)
                }
                if workID == homeID { Text("Choose two different stations.").foregroundStyle(.orange) }
                if let saveError { Text(saveError).foregroundStyle(.orange) }
                Text("Work shows trains from Home to Work; Home shows trains from Work to Home. Bart defaults to Work in the morning and Home in the afternoon. Your selection also applies to the desktop widget.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Only direct trains are shown. Routes that require a transfer aren't supported yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Desktop widget") {
                Text("Control-click your desktop, choose Edit Widgets, then search for Bart and drag a widget onto your desktop.")
                    .font(.callout)
                Text("The widget supports small, medium and large sizes. macOS manages its update frequency; the timestamp always shows when BART's data was last updated. Use its refresh button to request fresh predictions.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = store.widgetError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: store.setLogin))
                if let error = store.loginError { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("All times are Pacific. The menu bar checks BART every 30 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 585)
        .onChange(of: workID) { _, _ in saved = false }
        .onChange(of: homeID) { _, _ in saved = false }
    }

    private func saveStations() {
        guard let work = Station.station(id: workID), let home = Station.station(id: homeID) else { return }
        do { try store.setStations(work: work, home: home); saveError = nil; saved = true }
        catch { saveError = error.localizedDescription }
    }
}
