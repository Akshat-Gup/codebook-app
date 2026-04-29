import Foundation

struct RuntimePolicy {
    let readOnly: Bool
    let runtimeLoggingEnabled: Bool
    let persistentStorageEnabled: Bool

    /// True when the running binary passes a basic code-signature check.
    /// When false the app was likely redistributed (e.g. AirDrop) without proper signing.
    let codeSignatureValid: Bool

    static let shared = RuntimePolicy(
        environment: ProcessInfo.processInfo.environment,
        infoDictionary: Bundle.main.infoDictionary ?? [:]
    )

    init(environment: [String: String], infoDictionary: [String: Any]) {
        let readOnly = Self.resolveBool(
            environment: environment,
            infoDictionary: infoDictionary,
            envKey: "CODEBOOK_READ_ONLY",
            infoKey: "CodebookReadOnly",
            defaultValue: false
        )
        self.readOnly = readOnly
        self.runtimeLoggingEnabled = Self.resolveBool(
            environment: environment,
            infoDictionary: infoDictionary,
            envKey: "CODEBOOK_ENABLE_RUNTIME_LOGGING",
            infoKey: "CodebookEnableRuntimeLogging",
            defaultValue: !readOnly
        )
        self.persistentStorageEnabled = Self.resolveBool(
            environment: environment,
            infoDictionary: infoDictionary,
            envKey: "CODEBOOK_ENABLE_PERSISTENCE",
            infoKey: "CodebookEnablePersistence",
            defaultValue: !readOnly
        )
        self.codeSignatureValid = Self.verifyCodeSignature()
    }

    private static func resolveBool(
        environment: [String: String],
        infoDictionary: [String: Any],
        envKey: String,
        infoKey: String,
        defaultValue: Bool
    ) -> Bool {
        if let value = environment[envKey].flatMap(parseBool(_:)) {
            return value
        }
        if let value = infoDictionary[infoKey] as? Bool {
            return value
        }
        return defaultValue
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func verifyCodeSignature() -> Bool {
        #if DEBUG
        return true
        #else
        guard let executableURL = Bundle.main.executableURL else { return false }
        var staticCode: SecStaticCode?
        let pathStatus = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode)
        guard pathStatus == errSecSuccess, let code = staticCode else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
        #endif
    }
}
