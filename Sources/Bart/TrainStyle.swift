import AppKit
import SwiftUI

// Shared by the menu bar cards and the desktop widget so both read the same.
extension Train {
    func leavesLabel(at now: Date) -> String {
        departure > now ? "LEAVES IN \(departureCountdownValue(at: now).uppercased())" : "LEAVING"
    }

    var statusLabel: String {
        guard isLive else { return "SCHEDULED" }
        guard let delay = boardingDelay else { return "LIVE PREDICTION" }
        if delay == 0 { return "ON TIME" }
        let minutes = abs(delay) < 60 ? "<1" : String(Int(ceil(Double(abs(delay)) / 60)))
        if delay > 0 { return "LATE \(minutes == "<1" ? "" : "+")\(minutes) MIN" }
        return "EARLY \(minutes) MIN"
    }

    var statusColor: Color {
        guard isLive, let delay = boardingDelay else { return .secondary }
        if delay > 0 { return Color(red: 246.0 / 255, green: 73.0 / 255, blue: 50.0 / 255) }
        if delay == 0 { return Color(red: 70.0 / 255, green: 161.0 / 255, blue: 113.0 / 255) }
        return .secondary
    }
}

struct ClockText: View {
    let date: Date
    var size: CGFloat = 27
    var suffixSize: CGFloat = 12

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(Pacific.format(date)).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(Pacific.format(date, "a")).font(.system(size: suffixSize, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
        }.fixedSize()
    }
}

struct RouteLine: View {
    let journey: BARTJourney
    let minutes: Int
    var nameSize: CGFloat = 14
    var minutesSize: CGFloat = 12

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(journey.origin.name)
                .font(.system(size: nameSize, weight: .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.8).help(journey.origin.name)
            rule
            Text("\(minutes) MIN")
                .font(.system(size: minutesSize, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary).fixedSize()
            rule
            Text(journey.destination.name)
                .font(.system(size: nameSize, weight: .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.8).help(journey.destination.name)
        }
    }

    private var rule: some View {
        Capsule().fill(Color(nsColor: .separatorColor).opacity(0.65))
            .frame(minWidth: 12, maxWidth: .infinity).frame(height: 2)
            .accessibilityHidden(true)
    }
}

struct TrainStatusLine: View {
    let train: Train
    let now: Date
    var size: CGFloat = 12

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(train.leavesLabel(at: now))
            Text("·").accessibilityHidden(true)
            Text(train.statusLabel).foregroundStyle(train.statusColor)
            Spacer(minLength: 0)
        }
        .font(.system(size: size, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }
}
