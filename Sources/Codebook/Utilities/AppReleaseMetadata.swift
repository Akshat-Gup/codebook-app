import Foundation

struct AppReleaseMetadata {
    let version: String
    let build: String
    let githubRepository: String?
    let releasesURL: URL?
    let appcastURL: URL?
    let sparklePublicKey: String?

    static let current = AppReleaseMetadata(
        bundle: .main,
        environment: ProcessInfo.processInfo.environment
    )

    init(bundle: Bundle, environment: [String: String]) {
        let info = bundle.infoDictionary ?? [:]
        version = Self.stringValue(
            environment: environment,
            infoDictionary: info,
            environmentKey: "CODEBOOK_VERSION",
            infoKey: "CFBundleShortVersionString",
            defaultValue: "dev"
        )
        build = Self.stringValue(
            environment: environment,
            infoDictionary: info,
            environmentKey: "CODEBOOK_BUILD_NUMBER",
            infoKey: "CFBundleVersion",
            defaultValue: "0"
        )

        let repository = Self.optionalStringValue(
            environment: environment,
            infoDictionary: info,
            environmentKey: "CODEBOOK_GITHUB_REPOSITORY",
            infoKey: "CodebookGitHubRepository"
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let repository, !repository.isEmpty {
            githubRepository = repository
            releasesURL = URL(string: "https://github.com/\(repository)/releases")
        } else {
            githubRepository = nil
            releasesURL = nil
        }

        let appcast = Self.optionalStringValue(
            environment: environment,
            infoDictionary: info,
            environmentKey: "CODEBOOK_APPCAST_URL",
            infoKey: "SUFeedURL"
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        appcastURL = appcast.flatMap(URL.init(string:))

        sparklePublicKey = Self.optionalStringValue(
            environment: environment,
            infoDictionary: info,
            environmentKey: "CODEBOOK_SPARKLE_PUBLIC_ED_KEY",
            infoKey: "SUPublicEDKey"
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var versionDisplay: String {
        "\(version) (\(build))"
    }

    var sparkleConfigured: Bool {
        appcastURL != nil && sparklePublicKey?.isEmpty == false
    }

    private static func stringValue(
        environment: [String: String],
        infoDictionary: [String: Any],
        environmentKey: String,
        infoKey: String,
        defaultValue: String
    ) -> String {
        optionalStringValue(
            environment: environment,
            infoDictionary: infoDictionary,
            environmentKey: environmentKey,
            infoKey: infoKey
        ) ?? defaultValue
    }

    private static func optionalStringValue(
        environment: [String: String],
        infoDictionary: [String: Any],
        environmentKey: String,
        infoKey: String
    ) -> String? {
        if let environmentValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentValue.isEmpty {
            return environmentValue
        }
        if let stringValue = infoDictionary[infoKey] as? String,
           !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stringValue
        }
        return nil
    }
}
