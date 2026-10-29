import AppKit
import SwiftUI

struct BoardView: View {
    private static let headerIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject var store: BoardStore
    @State private var showingAdvisories = false
    var openSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if let icon = Self.headerIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.journey.destination.name) bound")
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(updateLabel).font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor)).monospacedDigit()
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Button { Task { await store.refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .disabled(store.refreshing).help("Refresh BART times (⌘R)")
                    .accessibilityLabel("Refresh BART times").keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(.plain).focusEffectDisabled()
                    Button { showingAdvisories.toggle() } label: {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .help(store.advisories.isEmpty ? "No service advisories" : "Service advisories (\(store.advisories.count))")
                    .accessibilityLabel(store.advisories.isEmpty ? "No service advisories" : "Service advisories (\(store.advisories.count))")
                    .buttonStyle(.plain).focusEffectDisabled()
                    .popover(isPresented: $showingAdvisories, arrowEdge: .bottom) { advisoryPopover }
                    Menu {
                        Button("Settings…", action: openSettings).keyboardShortcut(",", modifiers: .command)
                        Button("Add a desktop widget…") { openSettings() }
                        Button("Check for Updates…", action: checkForUpdates)
                        Divider()
                        Link("BART website", destination: URL(string: "https://www.bart.gov")!)
                        Button("Quit Bart") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
                    } label: {
                        Color.clear.frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .buttonStyle(.plain).focusEffectDisabled()
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                    .help("Settings and more")
                    .accessibilityLabel("Settings and more")
                }
            }
            .controlSize(.small).buttonStyle(.borderless)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            .zIndex(1)

            DestinationControl(
                selection: store.selectedDestination,
                workRoute: "\(store.stations.home.name) to \(store.stations.work.name)",
                homeRoute: "\(store.stations.work.name) to \(store.stations.home.name)",
                onSelect: store.selectDestination
            )
            .padding(.horizontal, 16).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 8) {
                    if let error = store.error, !showSkeleton {
                        Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if store.stale && store.feedTime != nil && !showSkeleton {
                        Label("Live data is out of date. Showing scheduled trains.", systemImage: "clock.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = store.scheduleError, store.upcomingTrains.isEmpty && !showSkeleton {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    if showSkeleton {
                        ForEach(0..<3, id: \.self) { index in
                            JourneyCard(train: placeholderTrain(index), journey: store.journey, now: store.now)
                                .redacted(reason: .placeholder)
                                .allowsHitTesting(false)
                                .accessibilityLabel("Loading train \(index + 1)")
                        }
                    } else {
                        ForEach(Array(store.upcomingTrains.enumerated()), id: \.element.id) { index, train in
                            JourneyCard(train: train, journey: store.journey, now: store.now)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("Train \(index + 1)")
                        }
                    }
                    if store.upcomingTrains.isEmpty && !showSkeleton {
                        VStack(spacing: 10) {
                            Image(systemName: "tram").font(.title2)
                            Text("No upcoming direct trains").font(.headline)
                            Text("This route may need a transfer, or service may have ended. Change stations in Settings or check BART's trip planner.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Link("Open BART trip planner", destination: URL(string: "https://www.bart.gov/planner")!)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showSkeleton)
            }.scrollIndicators(.hidden)
        }
        .frame(width: 420)
        .background {
            if reduceTransparency || contrast == .increased {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var updateLabel: String {
        if store.error != nil { return "Update failed" }
        guard let time = store.feedTime else { return "Connecting to BART…" }
        return "\(store.stale ? "Last live data at" : "Updated at") \(Pacific.format(time, "h:mm a"))"
    }

    private var showSkeleton: Bool {
        store.routeLoading || (store.refreshing && store.upcomingTrains.isEmpty)
    }

    private func placeholderTrain(_ index: Int) -> Train {
        let departure = store.now.addingTimeInterval(Double((index + 1) * 600))
        return Train(id: "loading-\(index)", originArrival: nil, originArrivalDelay: nil,
                     departure: departure, destinationArrival: departure.addingTimeInterval(26 * 60),
                     delay: nil, platform: "", headsign: "", isLive: false)
    }

    private var advisoryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service advisories").font(.headline)
            Divider()
            if store.advisories.isEmpty {
                Text("No current service advisories.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(store.advisories.enumerated()), id: \.offset) { index, advisory in
                            if index > 0 { Divider() }
                            Text(advisory).font(.callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(maxHeight: 240)
            }
        }.padding(16).frame(width: 320)
    }
}

private struct DestinationControl: View {
    let selection: CommuteDestination
    let workRoute: String
    let homeRoute: String
    let onSelect: (CommuteDestination) -> Void

    var body: some View {
        HStack(spacing: 6) {
            button("Work", .work, help: "To work: \(workRoute)")
            button("Home", .home, help: "To home: \(homeRoute)")
        }
        .controlSize(.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commute direction")
    }

    @ViewBuilder private func button(_ title: String, _ destination: CommuteDestination, help: String) -> some View {
        let label = Text(title).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity)
        Group {
            if selection == destination, #available(macOS 26.0, *) {
                Button { onSelect(destination) } label: { label }.buttonStyle(.glass)
            } else if selection == destination {
                Button { onSelect(destination) } label: { label }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            } else {
                Button { onSelect(destination) } label: { label.opacity(0.6) }.buttonStyle(.bordered)
            }
        }
        .help(help)
        .accessibilityAddTraits(selection == destination ? .isSelected : [])
    }
}

struct JourneyCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let train: Train
    let journey: BARTJourney
    let now: Date

    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency, contrast != .increased {
            content
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            GroupBox {
                content.padding(4)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(journey.origin.name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8).help(journey.origin.name)
                    Capsule().fill(Color(nsColor: .separatorColor).opacity(0.65))
                        .frame(minWidth: 12, maxWidth: .infinity).frame(height: 2)
                        .accessibilityHidden(true)
                    Text("\(train.rideMinutes) MIN")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary).fixedSize()
                    Capsule().fill(Color(nsColor: .separatorColor).opacity(0.65))
                        .frame(minWidth: 12, maxWidth: .infinity).frame(height: 2)
                        .accessibilityHidden(true)
                    Text(journey.destination.name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8).help(journey.destination.name)
                }
                HStack(alignment: .top) {
                    clock(train.boardingTime)
                    Spacer()
                    clock(train.destinationArrival)
                }.padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(train.departure > now
                         ? "LEAVES IN \(train.departureCountdownValue(at: now).uppercased())"
                         : "LEAVING")
                    Text("·").accessibilityHidden(true)
                    Text(statusLabel)
                        .foregroundStyle(statusColor)
                    Spacer(minLength: 0)
                }.font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
        }
    }

    private func clock(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(Pacific.format(date)).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(Pacific.format(date, "a")).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }.fixedSize()
    }

    private var statusLabel: String {
        guard train.isLive else { return "SCHEDULED" }
        guard let delay = train.boardingDelay else { return "LIVE PREDICTION" }
        if delay == 0 { return "ON TIME" }
        let minutes = abs(delay) < 60 ? "<1" : String(Int(ceil(Double(abs(delay)) / 60)))
        if delay > 0 { return "LATE \(minutes == "<1" ? "" : "+")\(minutes) MIN" }
        return "EARLY \(minutes) MIN"
    }

    private var statusColor: Color {
        guard train.isLive, let delay = train.boardingDelay else { return .secondary }
        if delay > 0 { return Color(red: 246.0 / 255, green: 73.0 / 255, blue: 50.0 / 255) }
        if delay == 0 { return Color(red: 70.0 / 255, green: 161.0 / 255, blue: 113.0 / 255) }
        return .secondary
    }
}
