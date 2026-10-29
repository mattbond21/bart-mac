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
        VStack(alignment: .leading, spacing: 5) {
            header
            if entry.trains.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Label("No upcoming direct trains", systemImage: "tram")
                        .font(.system(size: 13, weight: .medium))
                    Text(entry.snapshot.error ?? "Open Bart for the latest service information.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else if family == .systemLarge {
                ForEach(entry.trains) { train in largeCard(train) }
            } else if family == .systemSmall {
                smallJourney(entry.trains[0])
            } else {
                ForEach(entry.trains) { train in compactRow(train) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family == .systemSmall ? journey.destination.name : "\(journey.origin.name) → \(journey.destination.name)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(updateLabel).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(intent: RefreshBARTWidget()) { Image(systemName: "arrow.clockwise").font(.system(size: 12)) }
                .buttonStyle(.plain).accessibilityLabel("Refresh BART predictions")
        }
    }

    private var updateLabel: String {
        guard let time = entry.snapshot.feedTime else { return entry.snapshot.error == nil ? "Scheduled departures" : "Update unavailable" }
        let prefix = entry.isFresh ? (family == .systemSmall ? "Updated" : "BART updated") : (family == .systemSmall ? "Last data" : "Last live data")
        return "\(prefix) \(Pacific.format(time, "h:mm a"))"
    }

    private func tint(_ train: Train) -> Color {
        let displayHex = train.lineColorHex.uppercased() == "#FFFF33" ? "#E3B62A" : train.lineColorHex
        let hex = displayHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let number = UInt32(hex, radix: 16) else { return .secondary }
        return Color(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }

    private func time(_ date: Date, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(Pacific.format(date)).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(Pacific.format(date, "a")).font(.system(size: 10)).foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func delayLabel(_ train: Train) -> some View {
        HStack(spacing: 5) {
            if train.isLive, let delay = train.boardingDelayLabel, train.boardingDelay != 0 {
                Text(delay).foregroundStyle((train.boardingDelay ?? 0) > 0 ? lateColor : .secondary)
            }
        }.font(.system(size: 10)).lineLimit(1)
    }

    private var lateColor: Color {
        Color(red: 246.0 / 255, green: 73.0 / 255, blue: 50.0 / 255)
    }

    @ViewBuilder private func waiting(_ train: Train) -> some View {
        if entry.isFresh && train.departure > entry.date {
            VStack(alignment: .trailing, spacing: 0) {
                Text("Leaves in").foregroundStyle(.secondary)
                Text(timerInterval: entry.date...train.departure, countsDown: true, showsHours: false)
                    .monospacedDigit().fontDesign(.rounded).fontWeight(.semibold)
            }
        } else {
            Text(train.isLive && !entry.isFresh ? "Last estimate" : train.departureCountdown(at: entry.date))
                .fontDesign(.rounded)
        }
    }

    private func compactRow(_ train: Train) -> some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(tint(train)).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                time(train.boardingTime, size: 17)
                delayLabel(train)
            }
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            time(train.destinationArrival, size: 17)
            Spacer(minLength: 2)
            waiting(train).font(.system(size: 10)).frame(width: 57, alignment: .trailing)
        }.frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func largeCard(_ train: Train) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(journey.origin.name).lineLimit(1).minimumScaleFactor(0.8)
                Capsule().fill(Color.primary.opacity(0.12))
                    .frame(minWidth: 8, maxWidth: .infinity).frame(height: 1)
                    .accessibilityHidden(true)
                Text("\(train.rideMinutes) MIN")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary).fixedSize()
                Capsule().fill(Color.primary.opacity(0.12))
                    .frame(minWidth: 8, maxWidth: .infinity).frame(height: 1)
                    .accessibilityHidden(true)
                Text(journey.destination.name).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) { time(train.boardingTime, size: 18); delayLabel(train) }
                Spacer()
                time(train.destinationArrival, size: 18)
            }
            HStack(spacing: 4) {
                Text("Leaves in").foregroundStyle(.secondary)
                Text(timerInterval: entry.date...train.departure, countsDown: true, showsHours: false)
                    .monospacedDigit().fontDesign(.rounded).fontWeight(.bold)
                Spacer(minLength: 0)
            }.font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func smallJourney(_ train: Train) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(journey.origin.name).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            time(train.boardingTime, size: 26)
            delayLabel(train)
            HStack(spacing: 5) {
                Circle().fill(tint(train)).frame(width: 5, height: 5)
                Text("Arrives \(Pacific.format(train.destinationArrival, "h:mm a"))").font(.system(size: 11))
            }
            HStack(spacing: 4) {
                Text("Leaves in").foregroundStyle(.secondary)
                Text(timerInterval: entry.date...train.departure, countsDown: true, showsHours: false)
                    .monospacedDigit().fontDesign(.rounded).fontWeight(.bold)
            }.font(.system(size: 12))
            Spacer(minLength: 0)
        }
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
