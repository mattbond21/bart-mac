import Foundation

enum BartBuild {
    static let versionLabel: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }()

    static let channelLabel: String = {
        let channel = Bundle.main.object(forInfoDictionaryKey: "BartBuildChannel") as? String
        return channel == "release" ? "Release" : "Development"
    }()
}
