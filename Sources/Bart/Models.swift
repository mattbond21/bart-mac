import Foundation

enum Pacific {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    static func date(_ day: Date, minute: Int) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
    }

    static func format(_ date: Date, _ pattern: String = "h:mm") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func parse(_ date: String, _ time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM/dd/yyyy hh:mm a"
        return formatter.date(from: "\(date) \(time)")
    }
}

struct Train: Identifiable, Equatable, Codable {
    let id: String
    let originArrival: Date?
    let originArrivalDelay: Int?
    let departure: Date
    let destinationArrival: Date
    let delay: Int?
    let platform: String
    let headsign: String
    let isLive: Bool
    let lineName: String
    let lineColorHex: String

    init(id: String, originArrival: Date?, originArrivalDelay: Int?, departure: Date,
         destinationArrival: Date, delay: Int?, platform: String, headsign: String, isLive: Bool,
         lineName: String = "Direct train", lineColorHex: String = "#8E8E93") {
        self.id = id
        self.originArrival = originArrival
        self.originArrivalDelay = originArrivalDelay
        self.departure = departure
        self.destinationArrival = destinationArrival
        self.delay = delay
        self.platform = platform
        self.headsign = headsign
        self.isLive = isLive
        self.lineName = lineName
        self.lineColorHex = lineColorHex
    }

    var boardingDelay: Int? { originArrival != nil ? originArrivalDelay : delay }
    var boardingDelayLabel: String? { Self.delayLabel(for: boardingDelay) }

    var boardingTime: Date { originArrival ?? departure }
    var scheduledBoardingTime: Date? {
        guard isLive else { return nil }
        if let arrival = originArrival, let arrivalDelay = originArrivalDelay, arrivalDelay != 0 {
            return arrival.addingTimeInterval(-Double(arrivalDelay))
        }
        if originArrival == nil, let delay, delay != 0 { return scheduledDeparture }
        return nil
    }
    var scheduledDeparture: Date { departure.addingTimeInterval(-Double(delay ?? 0)) }
    var rideMinutes: Int { max(1, Int((destinationArrival.timeIntervalSince(departure) / 60).rounded())) }

    func countdown(at now: Date) -> String {
        if departure <= now { return "Leaving" }
        if let arrival = originArrival, arrival <= now { return "Boarding" }
        let minutes = Int(ceil(boardingTime.timeIntervalSince(now) / 60))
        return minutes < 1 ? "Due" : "\(minutes) min"
    }

    func departureCountdown(at now: Date) -> String {
        let remaining = departureCountdownValue(at: now)
        return remaining == "now" ? "Leaving now" : "Leaves in \(remaining)"
    }

    func departureCountdownValue(at now: Date) -> String {
        let seconds = departure.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let minutes = Int(ceil(seconds / 60))
        return "\(minutes) min"
    }

    var delayLabel: String? { Self.delayLabel(for: delay) }

    private static func delayLabel(for delay: Int?) -> String? {
        guard let delay else { return nil }
        if delay >= 60 { return "+\(Int(ceil(Double(delay) / 60))) min late" }
        if delay <= -60 { return "\(Int(ceil(Double(-delay) / 60))) min early" }
        if delay > 0 { return "<1 min late" }
        if delay < 0 { return "<1 min early" }
        return "On time"
    }
}

struct LiveBoard: Codable {
    let timestamp: Date
    let trains: [Train]
}

enum BoardError: LocalizedError {
    case invalidFeed(String)
    case http(Int)
    case invalidJourney
    var errorDescription: String? {
        switch self {
        case .invalidFeed(let message): return message
        case .http(let status): return "BART returned HTTP \(status)."
        case .invalidJourney: return "Choose two different stations."
        }
    }
}

enum Commute {
    static func trains(schedule: [Train], live: [Train], day: Date, start: Int, end: Int, now: Date) -> [Train] {
        let lower = Pacific.date(day, minute: start)
        let upper = Pacific.date(day, minute: end)
        // Use scheduled departure for membership so a delayed 5:10 train stays in the window.
        let relevantLive = live.filter { $0.scheduledDeparture >= lower.addingTimeInterval(-30) && $0.scheduledDeparture <= upper.addingTimeInterval(30) }
        let scheduled = schedule.filter { train in
            train.departure >= lower && train.departure <= upper && train.departure > now &&
            !relevantLive.contains { abs($0.scheduledDeparture.timeIntervalSince(train.departure)) < 90 }
        }
        return (scheduled + relevantLive.filter { $0.departure > now }).sorted { $0.departure < $1.departure }
    }
}
