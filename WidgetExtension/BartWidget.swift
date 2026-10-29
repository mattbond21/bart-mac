import AppIntents
import SwiftUI
import WidgetKit

enum BartWidgetIdentity {
    static let kind = "BARTDepartures"
}

struct BartEntry: TimelineEntry {
    let date: Date
    let snapshot: BoardSnapshot

    var trains: [Train] { Array(snapshot.trains.filter { $0.departure > date }.prefix(3)) }
    var isFresh: Bool {
        guard let time = snapshot.feedTime, snapshot.error == nil else { return false }
        return date.timeIntervalSince(time) <= 90 && time.timeIntervalSince(date) < 60
    }
}

enum WidgetBoardLoader {
    static func load(force: Bool = false) async -> BoardSnapshot {
        let now = Date()
        let journey = SharedBoardCache.journey
        let cached = SharedBoardCache.snapshot.flatMap { $0.journey == journey ? $0 : nil }
        if !force, let cached, now.timeIntervalSince(cached.fetchedAt) < 25 {
            return cached
        }
        let service = BARTService()
        let snapshot: BoardSnapshot
        do {
            let live = try await service.live(now: now, journey: journey)
            if now.timeIntervalSince(live.timestamp) <= 90, live.timestamp.timeIntervalSince(now) < 60, !live.trains.isEmpty {
                snapshot = BoardSnapshot(journey: journey, trains: Array(live.trains.prefix(3)), feedTime: live.timestamp, fetchedAt: now, error: nil)
            } else {
                let scheduled = try await service.departures(day: now, time: Pacific.format(now, "h:mm a"), journey: journey)
                snapshot = BoardSnapshot(journey: journey, trains: Array(scheduled.filter { $0.departure > now }.prefix(3)), feedTime: live.timestamp, fetchedAt: now, error: live.trains.isEmpty ? nil : "Live predictions are out of date.")
            }
        } catch {
            do {
                let scheduled = try await service.departures(day: now, time: Pacific.format(now, "h:mm a"), journey: journey)
                snapshot = BoardSnapshot(journey: journey, trains: Array(scheduled.filter { $0.departure > now }.prefix(3)), feedTime: cached?.feedTime, fetchedAt: now, error: "Live predictions unavailable.")
            } catch {
                snapshot = BoardSnapshot(journey: journey, trains: cached?.trains ?? [], feedTime: cached?.feedTime, fetchedAt: now, error: "Couldn't refresh BART. Open the app to try again.")
            }
        }
        if SharedBoardCache.journey == journey {
            do { try SharedBoardCache.saveSnapshot(snapshot) }
            catch { NSLog("BART widget couldn't save its shared snapshot: %@", error.localizedDescription) }
        }
        return snapshot
    }

    static var preview: BoardSnapshot {
        let now = Date()
        let trains = [4, 14, 24].enumerated().map { index, minutes in
            let arrival = now.addingTimeInterval(Double(minutes * 60))
            return Train(id: "preview-\(index)", originArrival: arrival, originArrivalDelay: index == 0 ? 180 : 0,
                         departure: arrival.addingTimeInterval(30), destinationArrival: arrival.addingTimeInterval(27 * 60),
                         delay: index == 0 ? 180 : 0, platform: "2", headsign: "Yellow line", isLive: true,
                         lineName: "Yellow line", lineColorHex: "#E3B62A")
        }
        return BoardSnapshot(journey: .home, trains: trains, feedTime: now, fetchedAt: now, error: nil)
    }
}

struct BartProvider: TimelineProvider {
    func placeholder(in context: Context) -> BartEntry { BartEntry(date: Date(), snapshot: WidgetBoardLoader.preview) }

    func getSnapshot(in context: Context, completion: @escaping (BartEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(BartEntry(date: Date(), snapshot: await WidgetBoardLoader.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BartEntry>) -> Void) {
        Task {
            var snapshot = await WidgetBoardLoader.load()
            if snapshot.journey != SharedBoardCache.journey { snapshot = await WidgetBoardLoader.load(force: true) }
            let now = Date()
            // Entries remove departed trains and mark expired predictions, even if a network reload is deferred.
            var dates = [now, now.addingTimeInterval(5 * 60), now.addingTimeInterval(15 * 60)]
            // The minute countdown changes each time a departure is a whole number of minutes away.
            for train in snapshot.trains {
                dates += (1...30).map { train.departure.addingTimeInterval(Double(-$0 * 60)) }
                    .filter { $0 > now && $0 < now.addingTimeInterval(30 * 60) }
            }
            dates += snapshot.trains.map { $0.departure.addingTimeInterval(1) }.filter { $0 > now && $0 < now.addingTimeInterval(15 * 60) }
            if let stamp = snapshot.feedTime, stamp.addingTimeInterval(91) > now { dates.append(stamp.addingTimeInterval(91)) }
            let entries = Array(Set(dates)).sorted().map { BartEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60))))
        }
    }
}

struct RefreshBARTWidget: AppIntent {
    static var title: LocalizedStringResource = "Refresh BART trains"
    static var description = IntentDescription("Updates the trains shown in your BART desktop widget.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        _ = await WidgetBoardLoader.load(force: true)
        WidgetCenter.shared.reloadTimelines(ofKind: BartWidgetIdentity.kind)
        return .result()
    }
}

struct BartWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: BartEntry
    private let previewFamily: WidgetFamily?

    init(entry: BartEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }

    private var family: WidgetFamily { previewFamily ?? systemFamily }

    private var journey: BARTJourney { entry.snapshot.journey }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
            header
            if entry.trains.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Label("No upcoming direct trains", systemImage: "tram")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text(entry.snapshot.error ?? "Open Bart for the latest service information.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else if family == .systemLarge {
                ForEach(entry.trains) { train in card(train) }
            } else if family == .systemSmall {
                smallJourney(entry.trains[0])
            } else {
                Spacer(minLength: 0)
                ForEach(entry.trains) { train in row(train) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(journey.destination.name) bound")
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(updateLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(intent: RefreshBARTWidget()) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("Refresh BART predictions")
        }
    }

    private var updateLabel: String {
        guard let time = entry.snapshot.feedTime else { return entry.snapshot.error == nil ? "Scheduled departures" : "Update unavailable" }
        let prefix = entry.isFresh ? (family == .systemSmall ? "Updated" : "Updated at") : (family == .systemSmall ? "Last data" : "Last live data at")
        return "\(prefix) \(Pacific.format(time, "h:mm a"))"
    }

    private func row(_ train: Train) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ClockText(date: train.boardingTime, size: 20, suffixSize: 10)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            ClockText(date: train.destinationArrival, size: 20, suffixSize: 10)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(train.leavesLabel(at: entry.date))
                Text(train.statusLabel).foregroundStyle(train.statusColor)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func card(_ train: Train) -> some View {
        VStack(spacing: 0) {
            RouteLine(journey: journey, minutes: train.rideMinutes, nameSize: 12, minutesSize: 10)
            Spacer(minLength: 2)
            HStack(alignment: .top) {
                ClockText(date: train.boardingTime, size: 22, suffixSize: 11)
                Spacer()
                ClockText(date: train.destinationArrival, size: 22, suffixSize: 11)
            }
            Spacer(minLength: 2)
            TrainStatusLine(train: train, now: entry.date, size: 11)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func smallJourney(_ train: Train) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            ClockText(date: train.boardingTime, size: 30, suffixSize: 12)
            Spacer(minLength: 0)
            Group {
                Text(train.leavesLabel(at: entry.date))
                Text(train.statusLabel).foregroundStyle(train.statusColor)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BARTTrainsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BartWidgetIdentity.kind, provider: BartProvider()) { entry in
            BartWidgetView(entry: entry)
        }
        .configurationDisplayName("Bart trains")
        .description("The next direct trains for the route selected in Bart settings.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#if !WIDGET_PREVIEW
@main
struct BartWidgetBundle: WidgetBundle {
    var body: some Widget { BARTTrainsWidget() }
}
#endif
