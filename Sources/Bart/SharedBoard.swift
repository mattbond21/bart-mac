import Foundation

struct BoardSnapshot: Codable {
    let journey: BARTJourney
    let trains: [Train]
    let feedTime: Date?
    let fetchedAt: Date
    let error: String?
}

enum SharedBoardCache {
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "BARTAppGroup") as? String ?? "5ERD8L276B.com.mattbond.bart.shared"
    }

    static var stations: CommuteStations {
        if let saved = read(CommuteStations.self, filename: "stations.json"), saved.isValid { return saved }
        if let legacy = read(BARTJourney.self, filename: "journey.json"), legacy.isValid {
            return CommuteStations(work: legacy.origin, home: legacy.destination)
        }
        return .standard
    }
    static var manualSelection: CommuteSelection? { read(CommuteSelection.self, filename: "selection.json") }
    static func selectedDestination(at date: Date) -> CommuteDestination {
        manualSelection?.destination(at: date) ?? .automatic(at: date)
    }
    static var journey: BARTJourney { stations.journey(to: selectedDestination(at: Date())) }
    static var snapshot: BoardSnapshot? { read(BoardSnapshot.self, filename: "board.json") }

    static func saveStations(_ stations: CommuteStations) throws {
        try write(stations, filename: "stations.json")
    }

    static func saveManualSelection(_ selection: CommuteSelection) throws {
        try write(selection, filename: "selection.json")
    }

    static func saveSnapshot(_ snapshot: BoardSnapshot) throws {
        if let existing = self.snapshot, existing.journey == snapshot.journey, existing.fetchedAt > snapshot.fetchedAt { return }
        try write(snapshot, filename: "board.json")
    }

    private static func directory() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw BoardError.invalidFeed("The shared widget container is unavailable. Use the signed app in Applications.")
        }
        let directory = url.appendingPathComponent("BART", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func read<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        guard let directory = try? directory(), let data = try? Data(contentsOf: directory.appendingPathComponent(filename)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, filename: String) throws {
        try JSONEncoder().encode(value).write(to: directory().appendingPathComponent(filename), options: .atomic)
    }
}
