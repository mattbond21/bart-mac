import Foundation
import Testing
@testable import Bart

private func varint(_ n: UInt64) -> Data {
    var n = n, result = Data()
    repeat { let byte = UInt8(n & 127); n >>= 7; result.append(byte | (n > 0 ? 128 : 0)) } while n > 0
    return result
}
private func number(_ field: Int, _ n: UInt64) -> Data { varint(UInt64(field << 3)) + varint(n) }
private func bytes(_ field: Int, _ data: Data) -> Data { varint(UInt64(field << 3 | 2)) + varint(UInt64(data.count)) + data }
private func string(_ field: Int, _ text: String) -> Data { bytes(field, Data(text.utf8)) }
private let base: UInt64 = 1_793_230_000
private let now = Date(timeIntervalSince1970: Double(base))
private func event(_ time: UInt64, delay: Int32 = 0) -> Data {
    number(1, UInt64(bitPattern: Int64(delay))) + number(2, time)
}
private func stop(_ id: String, arrival: UInt64, departure: UInt64, delay: Int32 = 0, arrivalDelay: Int32? = nil, relationship: UInt64 = 0) -> Data {
    string(4, id) + bytes(2, event(arrival, delay: arrivalDelay ?? delay)) + bytes(3, event(departure, delay: delay)) + number(5, relationship)
}
private func entity(id: String = "42", cancelled: Bool = false, reverse: Bool = false, skipped: Bool = false, delay: Int32 = 120, arrivalDelay: Int32? = nil) -> Data {
    let origin = stop("M20-2", arrival: base + 300, departure: base + 320, delay: delay, arrivalDelay: arrivalDelay)
    let destination = stop("C20-1", arrival: base + 1940, departure: base + 1960, relationship: skipped ? 1 : 0)
    let descriptor = string(1, id) + number(4, cancelled ? 3 : 0)
    return string(1, id) + bytes(3, bytes(1, descriptor) + (reverse ? bytes(2, destination) + bytes(2, origin) : bytes(2, origin) + bytes(2, destination)))
}
private func feed(_ entities: [Data]) -> Data {
    bytes(1, string(1, "2.0") + number(3, base)) + entities.reduce(Data()) { $0 + bytes(2, $1) }
}

private func routeEntity(origin: String, destination: String, route: String? = "2") -> Data {
    let descriptor = string(1, "fixture-trip") + number(4, 0) + (route.map { string(5, $0) } ?? Data())
    let origin = stop(origin, arrival: base + 300, departure: base + 330, delay: 120)
    let destination = stop(destination, arrival: base + 600, departure: base + 630)
    return string(1, "fixture-entity") + bytes(3, bytes(1, descriptor) + bytes(2, origin) + bytes(2, destination))
}

@Test func usesBothPredictionsWithoutAddingDelayTwice() throws {
    let board = try Realtime.decode(feed([entity()]), now: now)
    let train = try #require(board.trains.first)
    #expect(train.originArrival == now.addingTimeInterval(300))
    #expect(train.departure == now.addingTimeInterval(320))
    #expect(train.destinationArrival == now.addingTimeInterval(1940))
    #expect(train.delay == 120)
    #expect(train.scheduledDeparture == now.addingTimeInterval(200))
    #expect(train.platform == "2")
    #expect(train.countdown(at: now.addingTimeInterval(305)) == "Boarding")
    #expect(train.departureCountdown(at: now.addingTimeInterval(305)) == "Leaves in 1 min")
    #expect(train.departureCountdownValue(at: now.addingTimeInterval(305)) == "1 min")
    #expect(train.departureCountdown(at: now.addingTimeInterval(320)) == "Leaving now")
}

@Test func excludesCancelledSkippedWrongDirectionAndDuplicates() throws {
    let board = try Realtime.decode(feed([entity(), entity(), entity(id: "cancel", cancelled: true), entity(id: "reverse", reverse: true), entity(id: "skip", skipped: true)]), now: now)
    #expect(board.trains.map(\.id) == ["42"])
    #expect(try Realtime.decode(feed([entity()]), now: now.addingTimeInterval(321)).trains.isEmpty)
}

@Test func decodesNegativeDelay() throws {
    let train = try #require(Realtime.decode(feed([entity(delay: -90)]), now: now).trains.first)
    #expect(train.delay == -90)
    #expect(train.scheduledDeparture == now.addingTimeInterval(410))
}

@Test func originalArrivalUsesArrivalDelayRatherThanDepartureDelay() throws {
    let train = try #require(Realtime.decode(feed([entity(delay: 180, arrivalDelay: 120)]), now: now).trains.first)
    #expect(train.scheduledBoardingTime == now.addingTimeInterval(180))
    #expect(train.scheduledDeparture == now.addingTimeInterval(140))
    #expect(train.boardingDelay == 120)
    #expect(train.boardingDelayLabel == "+2 min late")
    #expect(train.delayLabel == "+3 min late")
    let onTime = try #require(Realtime.decode(feed([entity(delay: 180, arrivalDelay: 0)]), now: now).trains.first)
    #expect(onTime.scheduledBoardingTime == nil)
    #expect(onTime.boardingDelayLabel == "On time")
}

@Test func missingArrivalDelayDoesNotBorrowDepartureDelay() throws {
    let origin = string(4, "M20-2") + bytes(2, number(2, base + 300)) + bytes(3, event(base + 330, delay: 180))
    let destination = stop("C20-1", arrival: base + 1940, departure: base + 1960)
    let trip = bytes(1, string(1, "missing-arrival-delay")) + bytes(2, origin) + bytes(2, destination)
    let data = feed([string(1, "missing-arrival-delay") + bytes(3, trip)])
    let train = try #require(Realtime.decode(data, now: now).trains.first)
    #expect(train.boardingDelay == nil)
    #expect(train.boardingDelayLabel == nil)
    #expect(train.scheduledBoardingTime == nil)
    #expect(train.delayLabel == "+3 min late")
}

@Test func rejectsMalformedFeed() {
    for data in [Data([0]), Data([0x12, 0xff]), Data([0x08] + Array(repeating: UInt8(0xff), count: 11)), Data([0x09, 1])] {
        #expect(throws: (any Error).self) { try Realtime.decode(data, now: now) }
    }
}

@Test func selectedStationsDetermineLiveTrainDirection() throws {
    let embarcadero = try #require(Station.station(id: "EMBR"))
    let selectedJourney = BARTJourney(origin: .montgomery, destination: embarcadero)
    let data = feed([routeEntity(origin: "M20-1", destination: "M16-1", route: "1")])
    let train = try #require(Realtime.decode(data, now: now, journey: selectedJourney).trains.first)
    #expect(train.platform == "1")
    #expect(train.originArrival == now.addingTimeInterval(300))
    #expect(train.destinationArrival == now.addingTimeInterval(600))
    #expect(try Realtime.decode(data, now: now, journey: .home).trains.isEmpty)
    let opposite = BARTJourney(origin: embarcadero, destination: .montgomery)
    #expect(try Realtime.decode(data, now: now, journey: opposite).trains.isEmpty)
}

@Test func sameStationJourneyIsRejected() {
    let invalid = BARTJourney(origin: .montgomery, destination: .montgomery)
    #expect(!invalid.isValid)
    #expect(throws: (any Error).self) { try Realtime.decode(feed([]), now: now, journey: invalid) }
    #expect(throws: (any Error).self) { try BARTService.decodeDepartures([:], journey: invalid) }
}

@Test func stationMatchingIncludesConnectorPlatformsButNotSimilarPrefixes() throws {
    let coliseum = try #require(Station.station(id: "COLS"))
    let oaklandAirport = try #require(Station.station(id: "OAKL"))
    let data = feed([routeEntity(origin: "H10", destination: "H40", route: "19")])
    #expect(try Realtime.decode(data, now: now, journey: BARTJourney(origin: coliseum, destination: oaklandAirport)).trains.count == 1)
    #expect(Station.montgomery.matches(stopID: "M20-2"))
    #expect(!Station.montgomery.matches(stopID: "M200-2"))
    #expect(!Station.montgomery.matches(stopID: "ORIN"))
}

@Test func lineMetadataFollowsRouteAndUnknownTripsStayNeutral() throws {
    let blue = try #require(Realtime.decode(feed([routeEntity(origin: "M20-2", destination: "C20-1", route: "12")]), now: now).trains.first)
    #expect(blue.lineName == "Blue line")
    #expect(blue.lineColorHex == "#0099CC")
    let unknown = try #require(Realtime.decode(feed([routeEntity(origin: "M20-2", destination: "C20-1", route: nil)]), now: now).trains.first)
    #expect(unknown.lineName == "Direct train")
    #expect(unknown.lineColorHex == "#8E8E93")
    let encoded = try JSONEncoder().encode(unknown)
    #expect(try JSONDecoder().decode(Train.self, from: encoded) == unknown)
}

@Test func scheduleOnlyIncludesDirectTripsForSelectedStations() throws {
    let embarcadero = try #require(Station.station(id: "EMBR"))
    let journey = BARTJourney(origin: .montgomery, destination: embarcadero)
    let leg: [String: Any] = ["@origin": "MONT", "@destination": "EMBR", "@originPlatform": "PL 1", "@line": "ROUTE 1", "@trainHeadStation": "SFO Airport"]
    let timing: [String: Any] = ["@origTimeDate": "10/28/2026", "@origTimeMin": "04:50 PM", "@destTimeDate": "10/28/2026", "@destTimeMin": "04:52 PM"]
    var direct = timing
    direct["leg"] = [leg]
    var transfer = timing
    transfer["leg"] = [leg, leg]
    var otherRoute = timing
    otherRoute["leg"] = [["@origin": "MONT", "@destination": "ORIN"]]
    let root: [String: Any] = ["schedule": ["request": ["trip": [direct, transfer, otherRoute]]]]
    let trains = try BARTService.decodeDepartures(root, journey: journey)
    #expect(trains.count == 1)
    #expect(trains.first?.lineName == "Yellow line")
    #expect(trains.first?.platform == "1")
    #expect(trains.first?.scheduledBoardingTime == nil)
}

@Test func delayedEndOfWindowTrainStaysVisibleAndReplacesSchedule() throws {
    let day = try #require(Pacific.parse("10/28/2026", "12:00 PM"))
    let departure = Pacific.date(day, minute: 17 * 60 + 10)
    let scheduled = Train(id: "scheduled", originArrival: nil, originArrivalDelay: nil, departure: departure, destinationArrival: departure.addingTimeInterval(1620), delay: nil, platform: "2", headsign: "Antioch", isLive: false)
    let live = Train(id: "live", originArrival: departure.addingTimeInterval(280), originArrivalDelay: 300, departure: departure.addingTimeInterval(300), destinationArrival: departure.addingTimeInterval(1920), delay: 300, platform: "2", headsign: "Antioch", isLive: true)
    let result = Commute.trains(schedule: [scheduled], live: [live], day: day, start: 1000, end: 1030, now: departure.addingTimeInterval(-600))
    #expect(result.map(\.id) == ["live"])
}

@Test func pacificTimeAndWindowEndpoints() throws {
    let day = try #require(Pacific.parse("10/28/2026", "12:00 PM"))
    let trains = [999, 1000, 1030, 1031].map { minute in
        let dep = Pacific.date(day, minute: minute)
        return Train(id: "\(minute)", originArrival: nil, originArrivalDelay: nil, departure: dep, destinationArrival: dep.addingTimeInterval(1620), delay: nil, platform: "2", headsign: "Antioch", isLive: false)
    }
    #expect(Commute.trains(schedule: trains, live: [], day: day, start: 1000, end: 1030, now: day).map(\.id) == ["1000", "1030"])
    #expect(Pacific.format(Pacific.date(day, minute: 1000), "h:mm a") == "4:40 PM")
}

@Test func commuteDirectionUsesPacificNoonAndReversesStations() throws {
    let morning = try #require(Pacific.parse("10/29/2026", "11:59 AM"))
    let afternoon = try #require(Pacific.parse("10/29/2026", "12:00 PM"))
    let stations = CommuteStations(work: .montgomery, home: .orinda)
    #expect(CommuteDestination.automatic(at: morning) == .work)
    #expect(CommuteDestination.automatic(at: afternoon) == .home)
    #expect(stations.journey(to: .work) == BARTJourney(origin: .orinda, destination: .montgomery))
    #expect(stations.journey(to: .home) == BARTJourney(origin: .montgomery, destination: .orinda))
}

@Test func manualDirectionHoldsForThePacificDay() throws {
    let morning = try #require(Pacific.parse("10/29/2026", "8:00 AM"))
    let afternoon = try #require(Pacific.parse("10/29/2026", "5:00 PM"))
    let nextDay = try #require(Pacific.parse("10/30/2026", "8:00 AM"))
    let selection = CommuteSelection(destination: .home, at: morning)
    #expect(selection.destination(at: afternoon) == .home)
    #expect(selection.destination(at: nextDay) == nil)
    #expect(CommuteDestination.automatic(at: nextDay) == .work)
}
