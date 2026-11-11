import Foundation

nonisolated enum BroadcastDiagnosticCode: String, Codable, Sendable, CaseIterable {
    case missingExtension, ambiguousExtension, invalidExtension, invalidExtensionID, missingExecutable
    case noUsableGroup, notWritable, profileIssue, handshakeMismatch, startNotConfirmed, startNotPrepared, heartbeatLost
}

nonisolated struct BroadcastDiagnostic: Error, Codable, Equatable, Sendable {
    let code: BroadcastDiagnosticCode
    var candidateCount = 0
    var usableCount = 0
    var profileIssue = false
}

nonisolated enum BroadcastIdentifier {
    static func isValid(_ value: String) -> Bool {
        guard (1...255).contains(value.utf8.count) else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { component in
            guard !component.isEmpty else { return false }
            return component.utf8.allSatisfy { isAlphanumeric($0) || $0 == 45 }
        }
    }
    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
}

/// A bounded XML extraction, NOT a CMS signature/authenticity verification.
/// Only the group strings escape this scope; profiles are never logged or saved.
nonisolated struct BroadcastProfileGroups: Sendable {
    enum Status: Equatable, Sendable { case absent, available, noXML, malformed, oversized, missingEntitlements, unreadable }
    static let maximumBytes = 512 * 1024
    let groups: [String]
    let status: Status
    var hasIssue: Bool { status != .absent && status != .available }

    static func read(bundleURL: URL) -> Self {
        let url = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard FileManager.default.fileExists(atPath: url.path) else { return parse(nil) }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            return parse(try file.read(upToCount: maximumBytes + 1) ?? Data())
        } catch { return Self(groups: [], status: .unreadable) }
    }

    static func parse(_ data: Data?) -> Self {
        guard let data else { return Self(groups: [], status: .absent) }
        guard data.count <= maximumBytes else { return Self(groups: [], status: .oversized) }
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return Self(groups: [], status: .noXML)
        }
        do {
            let xml = data.subdata(in: start.lowerBound..<end.upperBound)
            guard let root = try PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any] else {
                return Self(groups: [], status: .malformed)
            }
            guard let entitlements = root["Entitlements"] as? [String: Any] else {
                return Self(groups: [], status: .missingEntitlements)
            }
            guard let raw = entitlements["com.apple.security.application-groups"] else {
                return Self(groups: [], status: .available)
            }
            guard let groups = raw as? [String], groups.count <= 64 else {
                return Self(groups: [], status: .malformed)
            }
            return Self(groups: Array(Set(groups.filter(BroadcastIdentifier.isValid))).sorted(), status: .available)
        } catch { return Self(groups: [], status: .malformed) }
    }
}

nonisolated struct BroadcastExtensionDescriptor: Sendable {
    let url: URL
    let identifier: String?
    let marker: Int?
    let point: String?
    let mode: String?
    let principal: String?
    let hasExecutable: Bool
    let configuredGroup: String?
}

nonisolated struct BroadcastGroupCandidate: Equatable, Sendable {
    enum Origin: String, Sendable { case commonProfile, singleProfile, configured, established }
    let identifier: String
    let origin: Origin
}

nonisolated struct BroadcastGroupEndpoint: Sendable {
    let candidate: BroadcastGroupCandidate
    let mailbox: BroadcastMailbox
}

nonisolated struct BroadcastRuntimeEnvironment: Sendable {
    let extensionID: String
    let endpoints: [BroadcastGroupEndpoint]
    let diagnostic: BroadcastDiagnostic
}

nonisolated enum BroadcastRuntime {
    static let establishedGroup = "group.azki.moye.MeloX"
    static let maximumCandidates = 8

    static func chooseExtension(_ descriptors: [BroadcastExtensionDescriptor]) throws -> BroadcastExtensionDescriptor {
        let marked = descriptors.filter { $0.marker == 1 }
        guard !marked.isEmpty else { throw BroadcastDiagnostic(code: .missingExtension) }
        guard marked.count == 1 else { throw BroadcastDiagnostic(code: .ambiguousExtension) }
        let item = marked[0]
        guard item.point == "com.apple.broadcast-services-upload", item.mode == "RPBroadcastProcessModeSampleBuffer",
              item.principal?.hasSuffix(".SampleHandler") == true else { throw BroadcastDiagnostic(code: .invalidExtension) }
        guard let identifier = item.identifier, BroadcastIdentifier.isValid(identifier) else {
            throw BroadcastDiagnostic(code: .invalidExtensionID)
        }
        guard item.hasExecutable else { throw BroadcastDiagnostic(code: .missingExecutable) }
        return item
    }

    static func candidates(host: BroadcastProfileGroups, upload: BroadcastProfileGroups,
                           configured: [String]) -> [BroadcastGroupCandidate] {
        var result: [BroadcastGroupCandidate] = []
        func append(_ groups: [String], origin: BroadcastGroupCandidate.Origin) {
            let sorted = Array(Set(groups.filter(BroadcastIdentifier.isValid))).sorted {
                if ($0 == establishedGroup) != ($1 == establishedGroup) { return $0 == establishedGroup }
                return $0 < $1
            }
            for group in sorted where !result.contains(where: { $0.identifier == group }) {
                result.append(BroadcastGroupCandidate(identifier: group, origin: origin))
            }
        }
        if host.status == .available && upload.status == .available {
            append(Array(Set(host.groups).intersection(upload.groups)), origin: .commonProfile)
        } else if host.status == .available { append(host.groups, origin: .singleProfile) }
        else if upload.status == .available { append(upload.groups, origin: .singleProfile) }
        append(configured, origin: .configured)
        append([establishedGroup], origin: .established)
        // Reserve room for the configured/established fallbacks even in a profile
        // with many unrelated groups. Both processes use this exact ordering.
        let fallbacks = result.filter { $0.origin == .configured || $0.origin == .established }
        let preferred = result.filter { $0.origin == .commonProfile || $0.origin == .singleProfile }
        return Array(preferred.prefix(maximumCandidates - min(fallbacks.count, maximumCandidates))) + Array(fallbacks.prefix(maximumCandidates))
    }

    static func probe(_ candidates: [BroadcastGroupCandidate], profileIssue: Bool,
                      container: (String) -> URL?) throws -> [BroadcastGroupEndpoint] {
        var endpoints: [BroadcastGroupEndpoint] = []
        var foundContainer = false
        for candidate in candidates.prefix(maximumCandidates) where BroadcastIdentifier.isValid(candidate.identifier) {
            guard let url = container(candidate.identifier) else { continue }
            foundContainer = true
            do {
                let mailbox = try BroadcastMailbox(container: url)
                let probe = mailbox.root.appendingPathComponent("probe-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: probe) }
                try Data([0x4d]).write(to: probe, options: .withoutOverwriting)
                guard try Data(contentsOf: probe) == Data([0x4d]) else { continue }
                try FileManager.default.removeItem(at: probe)
                endpoints.append(BroadcastGroupEndpoint(candidate: candidate, mailbox: mailbox))
            } catch { continue }
        }
        guard !endpoints.isEmpty else {
            throw BroadcastDiagnostic(code: foundContainer ? .notWritable : .noUsableGroup,
                                      candidateCount: candidates.count, profileIssue: profileIssue)
        }
        return endpoints
    }

    static func discover(host: Bundle) throws -> BroadcastExtensionDescriptor {
        guard let plugins = host.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: [.isSymbolicLinkKey]),
              urls.count <= 64 else { throw BroadcastDiagnostic(code: .missingExtension) }
        let descriptors = urls.filter { $0.pathExtension == "appex" }.compactMap { url -> BroadcastExtensionDescriptor? in
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let bundle = Bundle(url: url) else { return nil }
            let info = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
            let attributes = info?["NSExtensionAttributes"] as? [String: Any]
            let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? ""
            let safeName = !executable.isEmpty && executable != "." && executable != ".." && !executable.contains("/") && !executable.contains("\\")
            let executableURL = url.appendingPathComponent(executable)
            let properties = safeName ? (try? executableURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])) : nil
            return BroadcastExtensionDescriptor(url: url, identifier: bundle.bundleIdentifier,
                marker: bundle.object(forInfoDictionaryKey: "MeloXRecognitionBroadcastVersion") as? Int,
                point: info?["NSExtensionPointIdentifier"] as? String, mode: attributes?["RPBroadcastProcessMode"] as? String,
                principal: info?["NSExtensionPrincipalClass"] as? String,
                hasExecutable: properties?.isRegularFile == true && properties?.isSymbolicLink != true,
                configuredGroup: bundle.object(forInfoDictionaryKey: "MeloXBroadcastAppGroup") as? String)
        }
        return try chooseExtension(descriptors)
    }

    static func environment(host: Bundle, runningExtension: URL? = nil) throws -> BroadcastRuntimeEnvironment {
        let upload = try discover(host: host)
        guard runningExtension == nil || runningExtension?.standardizedFileURL == upload.url.standardizedFileURL else {
            throw BroadcastDiagnostic(code: .invalidExtension)
        }
        guard let extensionID = upload.identifier else { throw BroadcastDiagnostic(code: .invalidExtensionID) }
        let hostProfile = BroadcastProfileGroups.read(bundleURL: host.bundleURL)
        let uploadProfile = BroadcastProfileGroups.read(bundleURL: upload.url)
        let groups = candidates(host: hostProfile, upload: uploadProfile,
            configured: [host.object(forInfoDictionaryKey: "MeloXBroadcastAppGroup") as? String, upload.configuredGroup].compactMap { $0 })
        let issue = hostProfile.hasIssue || uploadProfile.hasIssue
        let endpoints = try probe(groups, profileIssue: issue) { group in
            #if os(iOS)
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            #else
            return nil
            #endif
        }
        return BroadcastRuntimeEnvironment(extensionID: extensionID, endpoints: endpoints,
            diagnostic: BroadcastDiagnostic(code: .startNotConfirmed, candidateCount: groups.count,
                                            usableCount: endpoints.count, profileIssue: issue))
    }

    static func enclosingHost(extensionURL: URL) throws -> Bundle {
        let plugins = extensionURL.deletingLastPathComponent()
        let hostURL = plugins.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns", hostURL.pathExtension == "app",
              let host = Bundle(url: hostURL) else { throw BroadcastDiagnostic(code: .invalidExtension) }
        return host
    }
}
