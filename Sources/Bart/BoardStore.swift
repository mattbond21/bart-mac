import Combine
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class BoardStore: ObservableObject {
    @Published private(set) var stations: CommuteStations
    @Published private(set) var selectedDestination: CommuteDestination
    @Published private(set) var journey: BARTJourney
    @Published var live: [Train] = []
    @Published var nextScheduled: [Train] = []
    @Published var advisories: [String] = []
    @Published var now = Date()
    @Published var feedTime: Date?
    @Published var error: String?
    @Published var scheduleError: String?
    @Published var refreshing = false
    @Published private(set) var routeLoading = false
    @Published var widgetError: String?
    @Published var loginError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let defaults = UserDefaults.standard
    private let service = BARTService()
    private var scheduleFetched: Date?
    private var alertsFetched: Date?
    private var loop: Task<Void, Never>?
    private var refreshAgain = false
    private var lastWidgetReload: Date?
    private var manualSelection: CommuteSelection?

    init() {
        let savedWork = defaults.string(forKey: "workStation").flatMap(Station.station)
        let savedHome = defaults.string(forKey: "homeStation").flatMap(Station.station)
        let legacyWork = defaults.string(forKey: "originStation").flatMap(Station.station)
        let legacyHome = defaults.string(forKey: "destinationStation").flatMap(Station.station)
        let resolvedStations: CommuteStations
        if let savedWork, let savedHome, savedWork != savedHome {
            resolvedStations = CommuteStations(work: savedWork, home: savedHome)
        } else if let legacyWork, let legacyHome, legacyWork != legacyHome {
            resolvedStations = CommuteStations(work: legacyWork, home: legacyHome)
        } else {
            resolvedStations = SharedBoardCache.stations
        }
        let selection = SharedBoardCache.manualSelection
        let destination = selection?.destination(at: Date()) ?? .automatic(at: Date())
        stations = resolvedStations
        manualSelection = selection
        selectedDestination = destination
        journey = resolvedStations.journey(to: destination)
        if let snapshot = SharedBoardCache.snapshot, snapshot.journey == journey {
            live = snapshot.trains.filter(\.isLive)
            nextScheduled = snapshot.trains.filter { !$0.isLive }
            feedTime = snapshot.feedTime
        }
    }

    var stale: Bool { feedTime.map { now.timeIntervalSince($0) > 90 || $0.timeIntervalSince(now) > 60 } ?? true }
    var liveTrains: [Train] { live.filter { $0.departure > now } }
    var upcomingTrains: [Train] {
        let predictions = stale ? [] : liveTrains
        let scheduled = nextScheduled.filter { train in
            train.departure > now && !predictions.contains { abs($0.scheduledDeparture.timeIntervalSince(train.departure)) < 90 }
        }
        return Array((predictions + scheduled).sorted { $0.departure < $1.departure }.prefix(3))
    }
    var menuTitle: String {
        guard let train = upcomingTrains.first else { return "\(journey.destination.name) —" }
        return "\(journey.destination.name) \(train.departureCountdown(at: now))"
    }
    var menuIsLive: Bool { upcomingTrains.first?.isLive == true && !stale }

    func setStations(work: Station, home: Station) throws {
        let updated = CommuteStations(work: work, home: home)
        guard updated.isValid else { throw BoardError.invalidJourney }
        guard updated != stations else { return }
        defaults.set(work.id, forKey: "workStation")
        defaults.set(home.id, forKey: "homeStation")
        defaults.set(work.id, forKey: "originStation")
        defaults.set(home.id, forKey: "destinationStation")
        stations = updated
        do { try SharedBoardCache.saveStations(updated); widgetError = nil }
        catch { widgetError = error.localizedDescription }
        changeJourney(to: updated.journey(to: selectedDestination))
        WidgetCenter.shared.reloadTimelines(ofKind: "BARTDepartures")
    }

    func selectDestination(_ destination: CommuteDestination) {
        let selection = CommuteSelection(destination: destination, at: Date())
        manualSelection = selection
        do { try SharedBoardCache.saveManualSelection(selection); widgetError = nil }
        catch { widgetError = error.localizedDescription }
        if selectedDestination != destination {
            selectedDestination = destination
            changeJourney(to: stations.journey(to: destination))
            WidgetCenter.shared.reloadTimelines(ofKind: "BARTDepartures")
        }
    }

    func start() {
        guard loop == nil else { return }
        do { try SharedBoardCache.saveStations(stations) }
        catch { widgetError = error.localizedDescription }
        loop = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                guard let self else { break }
                self.now = Date()
                self.updateAutomaticDestination(at: self.now)
                if ticks % 3 == 0 { await self.refresh() }
                ticks += 1
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func refresh(force: Bool = false) async {
        guard !refreshing else { if force { refreshAgain = true }; return }
        refreshing = true
        refreshAgain = false
        let route = journey
        defer {
            refreshing = false
            if route == journey { routeLoading = false }
            if refreshAgain { refreshAgain = false; Task { await refresh(force: true) } }
        }
        now = Date()
        let liveTask = Task { try await service.live(now: now, journey: route) }
        let needsSchedule = force || (scheduleFetched.map { now.timeIntervalSince($0) > 180 } ?? true)
        let scheduleTask = needsSchedule ? Task { try await service.departures(day: now, time: Pacific.format(now, "h:mm a"), journey: route) } : nil
        let needsAlerts = force || (alertsFetched.map { now.timeIntervalSince($0) > 120 } ?? true)
        let alertTask = needsAlerts ? Task { try await service.advisories() } : nil
        do {
            let board = try await liveTask.value
            guard route == journey else { return }
            live = board.trains; feedTime = board.timestamp; error = nil
        } catch {
            guard route == journey else { return }
            self.error = "Couldn't update live predictions. \(error.localizedDescription)"
        }
        if let scheduleTask {
            do {
                let trains = try await scheduleTask.value
                guard route == journey else { return }
                nextScheduled = trains; scheduleFetched = Date(); scheduleError = nil
            } catch {
                guard route == journey else { return }
                scheduleError = "Couldn't load the schedule. \(error.localizedDescription)"
            }
        }
        if let alertTask {
            do { advisories = try await alertTask.value; alertsFetched = Date() }
            catch { alertsFetched = nil }
        }
        now = Date()
        do {
            try SharedBoardCache.saveSnapshot(BoardSnapshot(journey: journey, trains: upcomingTrains, feedTime: feedTime, fetchedAt: now, error: error))
            widgetError = nil
            if force || (lastWidgetReload.map { now.timeIntervalSince($0) >= 60 } ?? true) {
                WidgetCenter.shared.reloadTimelines(ofKind: "BARTDepartures")
                lastWidgetReload = now
            }
        } catch { widgetError = error.localizedDescription }
    }

    private func updateAutomaticDestination(at date: Date) {
        let destination = manualSelection?.destination(at: date) ?? .automatic(at: date)
        guard destination != selectedDestination else { return }
        selectedDestination = destination
        changeJourney(to: stations.journey(to: destination))
        WidgetCenter.shared.reloadTimelines(ofKind: "BARTDepartures")
    }

    private func changeJourney(to updated: BARTJourney) {
        guard updated != journey else { return }
        routeLoading = true
        journey = updated
        live = []; nextScheduled = []; feedTime = nil; error = nil; scheduleError = nil; scheduleFetched = nil
        refreshAgain = true
        Task { await refresh(force: true) }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "Allow Bart in System Settings → General → Login Items." : nil
        } catch { loginError = error.localizedDescription }
    }
}
