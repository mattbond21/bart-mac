import Foundation

// Only the standard GTFS-RT fields needed for this route are decoded. Unknown fields are skipped.
struct ProtoMessage {
    enum Value { case number(UInt64), bytes(Data) }
    var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        let bytes = Array(data)
        var index = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < bytes.count else { throw BoardError.invalidFeed("Truncated live feed.") }
                let byte = bytes[index]; index += 1
                if shift == 63 && byte > 1 { throw BoardError.invalidFeed("Invalid live feed number.") }
                result |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return result }
            }
            throw BoardError.invalidFeed("Invalid live feed number.")
        }
        while index < bytes.count {
            let tag = try varint()
            let field = Int(tag >> 3)
            guard field > 0 else { throw BoardError.invalidFeed("Invalid live feed field.") }
            switch tag & 7 {
            case 0: fields[field, default: []].append(.number(try varint()))
            case 2:
                let size = try varint()
                guard size <= UInt64(bytes.count - index) else { throw BoardError.invalidFeed("Truncated live feed field.") }
                let end = index + Int(size)
                fields[field, default: []].append(.bytes(Data(bytes[index..<end])))
                index = end
            case 1, 5:
                index += (tag & 7 == 1) ? 8 : 4
                guard index <= bytes.count else { throw BoardError.invalidFeed("Truncated live feed.") }
            default: throw BoardError.invalidFeed("Unsupported live feed encoding.")
            }
        }
    }

    func number(_ field: Int) -> UInt64? {
        if case .number(let n) = fields[field]?.first { return n }; return nil
    }
    func bytes(_ field: Int) -> [Data] {
        (fields[field] ?? []).compactMap { if case .bytes(let data) = $0 { return data }; return nil }
    }
    func string(_ field: Int) -> String? { bytes(field).first.flatMap { String(data: $0, encoding: .utf8) } }
    func message(_ field: Int) throws -> ProtoMessage? { try bytes(field).first.map(ProtoMessage.init) }
}

enum Realtime {
    static func decode(_ data: Data, now: Date, journey: BARTJourney = .home) throws -> LiveBoard {
        guard journey.isValid else { throw BoardError.invalidJourney }
        let feed = try ProtoMessage(data)
        guard let timestamp = try feed.message(1)?.number(3) else {
            throw BoardError.invalidFeed("BART's live feed has no update time.")
        }
        var trains: [Train] = []
        var seen = Set<String>()
        for entityData in feed.bytes(2) {
            let entity = try ProtoMessage(entityData)
            guard entity.number(2) != 1, let trip = try entity.message(3),
                  let descriptor = try trip.message(1), let id = descriptor.string(1),
                  ![UInt64(3), 7].contains(descriptor.number(4) ?? 0) else { continue }
            let stops = try trip.bytes(2).map(ProtoMessage.init)
            guard let originIndex = stops.firstIndex(where: { journey.origin.matches(stopID: $0.string(4)) }),
                  let destinationIndex = stops.firstIndex(where: { journey.destination.matches(stopID: $0.string(4)) }),
                  originIndex < destinationIndex else { continue }
            let origin = stops[originIndex], destination = stops[destinationIndex]
            guard ![UInt64(1), 2].contains(origin.number(5) ?? 0),
                  ![UInt64(1), 2].contains(destination.number(5) ?? 0),
                  let departure = try origin.message(3), let departureTime = departure.number(2),
                  let arrivalTime = try destination.message(2)?.number(2) else { continue }
            let dep = Date(timeIntervalSince1970: Double(departureTime))
            let arr = Date(timeIntervalSince1970: Double(arrivalTime))
            guard dep > now, arr > dep, seen.insert(id).inserted else { continue }
            let originArrivalEvent = try origin.message(2)
            let originArrival = originArrivalEvent?.number(2).map { Date(timeIntervalSince1970: Double($0)) }
            let originArrivalDelay = originArrivalEvent?.number(1).map { Int(Int32(truncatingIfNeeded: $0)) }
            let delay = departure.number(1).map { Int(Int32(truncatingIfNeeded: $0)) }
            let line = BARTLine.route(descriptor.string(5)) ?? BARTLine.trip(id) ?? .unknown
            let platform = origin.string(4)?.split(separator: "-", maxSplits: 1).dropFirst().first.map(String.init) ?? "—"
            trains.append(Train(
                id: id, originArrival: originArrival, originArrivalDelay: originArrivalDelay,
                departure: dep, destinationArrival: arr,
                delay: delay, platform: platform,
                headsign: "\(line.name) · toward \(journey.destination.name)", isLive: true,
                lineName: line.name, lineColorHex: line.colorHex
            ))
        }
        return LiveBoard(timestamp: Date(timeIntervalSince1970: Double(timestamp)), trains: trains.sorted { $0.departure < $1.departure })
    }

}
