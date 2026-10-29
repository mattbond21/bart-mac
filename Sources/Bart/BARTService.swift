import Foundation

struct BARTService {
    static let publicKey = "MW9S-E7SL-26DU-VV8V"

    func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        request.setValue("Bart/1.0 (personal BART departure board)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BoardError.invalidFeed("No response from BART.") }
        guard (200..<300).contains(http.statusCode) else { throw BoardError.http(http.statusCode) }
        return data
    }

    func live(now: Date, journey: BARTJourney = .home) async throws -> LiveBoard {
        guard journey.isValid else { throw BoardError.invalidJourney }
        return try Realtime.decode(await data(URL(string: "https://api.bart.gov/gtfsrt/tripupdate.aspx")!), now: now, journey: journey)
    }

    func schedule(day: Date, start: Int, end: Int, journey: BARTJourney = .home) async throws -> [Train] {
        var results: [Train] = []
        var cursor = Pacific.date(day, minute: start)
        let upper = Pacific.date(day, minute: end)
        for _ in 0..<8 {
            let page = try await departures(day: day, time: Pacific.format(cursor, "h:mm a"), journey: journey)
            results += page.filter { $0.departure >= Pacific.date(day, minute: start) && $0.departure <= upper }
            guard let last = page.last?.departure, last < upper, last >= cursor else { break }
            cursor = last.addingTimeInterval(60)
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }.sorted { $0.departure < $1.departure }
    }

    func departures(day: Date, time: String, journey: BARTJourney = .home) async throws -> [Train] {
        guard journey.isValid else { throw BoardError.invalidJourney }
        let root = try await json("sched", query: [
            "cmd": "depart", "orig": journey.origin.id, "dest": journey.destination.id, "date": Pacific.format(day, "MM/dd/yyyy"),
            "time": time, "b": "0", "a": "3"
        ])
        return try Self.decodeDepartures(root, journey: journey)
    }

    static func decodeDepartures(_ root: [String: Any], journey: BARTJourney) throws -> [Train] {
        guard journey.isValid else { throw BoardError.invalidJourney }
        guard let schedule = root["schedule"] as? [String: Any],
              let request = schedule["request"] as? [String: Any] else {
            throw BoardError.invalidFeed("BART's schedule is unavailable.")
        }
        return Self.array(request["trip"]).compactMap { trip in
            let legs = array(trip["leg"])
            guard legs.count == 1, let leg = legs.first,
                  leg["@origin"] as? String == journey.origin.id, leg["@destination"] as? String == journey.destination.id,
                  let d = trip["@origTimeDate"] as? String, let t = trip["@origTimeMin"] as? String,
                  let ad = trip["@destTimeDate"] as? String, let at = trip["@destTimeMin"] as? String,
                  let departure = Pacific.parse(d, t), let arrival = Pacific.parse(ad, at), arrival > departure else { return nil }
            let line = BARTLine.route(leg["@line"] as? String) ?? .unknown
            return Train(id: "scheduled-\(departure.timeIntervalSince1970)", originArrival: nil, originArrivalDelay: nil,
                         departure: departure, destinationArrival: arrival, delay: nil,
                         platform: (leg["@originPlatform"] as? String ?? "—").replacingOccurrences(of: "PL ", with: ""),
                         headsign: leg["@trainHeadStation"] as? String ?? line.name, isLive: false,
                         lineName: line.name, lineColorHex: line.colorHex)
        }.sorted { $0.departure < $1.departure }
    }

    func advisories() async throws -> [String] {
        let root = try await json("bsa", query: ["cmd": "bsa"])
        return Self.array(root["bsa"]).compactMap { item in
            let text = (item["description"] as? [String: Any])?["#cdata-section"] as? String
            guard let text, !text.localizedCaseInsensitiveContains("no delays reported") else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func json(_ endpoint: String, query: [String: String]) async throws -> [String: Any] {
        var url = URLComponents(string: "https://api.bart.gov/api/\(endpoint).aspx")!
        url.queryItems = (query.merging(["key": Self.publicKey, "json": "y"]) { _, new in new }).map(URLQueryItem.init)
        let object = try JSONSerialization.jsonObject(with: await data(url.url!))
        guard let envelope = object as? [String: Any], let root = envelope["root"] as? [String: Any] else {
            throw BoardError.invalidFeed("BART returned an unreadable response.")
        }
        return root
    }

    static func array(_ value: Any?) -> [[String: Any]] {
        if let list = value as? [[String: Any]] { return list }
        if let item = value as? [String: Any] { return [item] }
        return []
    }
}
