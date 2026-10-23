import CryptoKit
import Foundation

// TestFlight release pipeline: version checks, the xcodegen/archive/upload commands, and the
// App Store Connect calls that wait for processing, add the build to a group and invite testers.
// TestFlightCLI.swift wires this to real processes and the network; TestFlightTests.swift drives it with fakes.

struct ReleaseVersion: Equatable, CustomStringConvertible {
    var marketing: String
    var build: Int
    var description: String { "\(marketing) (\(build))" }
}

enum ReleaseError: Error, Equatable, CustomStringConvertible {
    case missingSetting(String, file: String)
    case invalidMarketingVersion(String)
    case versionMismatch(ios: ReleaseVersion, mac: ReleaseVersion)
    case buildNumberUsed(ReleaseVersion, latest: Int)
    case commandFailed(String, status: Int32, log: String)
    case invalidEmail(String)
    case groupRequired
    case groupNotFound(String)
    case buildRejected(ReleaseVersion, state: String)
    case buildNotProcessed(ReleaseVersion)
    case credentialsRequired(String)
    case badKey(String)
    case api(status: Int, method: String, path: String, detail: String)

    var description: String {
        switch self {
        case let .missingSetting(key, file): return "\(key) not found in \(file)"
        case let .invalidMarketingVersion(value): return "Marketing version \(value) is not numeric X.Y.Z (see VERSIONING.md)"
        case let .versionMismatch(ios, mac): return "\(VersionFiles.projectPath) is \(ios) but \(VersionFiles.plistPath) is \(mac); align them first"
        case let .buildNumberUsed(version, latest): return "Build \(version.build) is not above App Store Connect's latest build \(latest); bump CURRENT_PROJECT_VERSION"
        case let .commandFailed(name, status, log): return "\(name) exited with status \(status); see \(log)"
        case let .invalidEmail(value): return "Not an email address: \(value)"
        case .groupRequired: return "Inviting testers needs --group"
        case let .groupNotFound(name): return "No TestFlight group named \"\(name)\""
        case let .buildRejected(version, state): return "App Store Connect marked \(version) \(state)"
        case let .buildNotProcessed(version): return "\(version) did not finish processing in time"
        case let .credentialsRequired(what): return "\(what) needs ASC_KEY_ID and ASC_ISSUER_ID (and the .p8 key)"
        case let .badKey(why): return "App Store Connect key: \(why)"
        case let .api(status, method, path, detail): return "\(method) \(path) failed (\(status)): \(detail)"
        }
    }
}

enum VersionFiles {
    static let projectPath = "Assets/ios/project.yml"
    static let plistPath = "Resources/Info.plist"

    static func read(root: URL) throws -> ReleaseVersion {
        let yaml = try String(contentsOf: root.appendingPathComponent(projectPath), encoding: .utf8)
        let plist = try Data(contentsOf: root.appendingPathComponent(plistPath))
        return try aligned(projectYAML: yaml, plist: plist)
    }

    static func aligned(projectYAML: String, plist: Data) throws -> ReleaseVersion {
        let ios = try project(projectYAML), mac = try infoPlist(plist)
        guard ios == mac else { throw ReleaseError.versionMismatch(ios: ios, mac: mac) }
        return ios
    }

    static func project(_ yaml: String) throws -> ReleaseVersion {
        func value(_ key: String) throws -> String {
            for line in yaml.split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                guard text.hasPrefix(key + ":") else { continue }
                return text.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            }
            throw ReleaseError.missingSetting(key, file: projectPath)
        }
        let marketing = try value("MARKETING_VERSION")
        let parts = marketing.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            throw ReleaseError.invalidMarketingVersion(marketing)
        }
        guard let build = Int(try value("CURRENT_PROJECT_VERSION")) else { throw ReleaseError.missingSetting("CURRENT_PROJECT_VERSION", file: projectPath) }
        return ReleaseVersion(marketing: marketing, build: build)
    }

    static func infoPlist(_ data: Data) throws -> ReleaseVersion {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        guard let marketing = plist["CFBundleShortVersionString"] as? String else { throw ReleaseError.missingSetting("CFBundleShortVersionString", file: plistPath) }
        guard let build = (plist["CFBundleVersion"] as? String).flatMap(Int.init) else { throw ReleaseError.missingSetting("CFBundleVersion", file: plistPath) }
        return ReleaseVersion(marketing: marketing, build: build)
    }
}

// MARK: - Build and upload

struct Command: Equatable {
    var name: String
    var tool: String
    var arguments: [String]
    var environment: [String: String] = [:]
    var log: String
}

protocol CommandRunning {
    func run(_ command: Command) throws -> Int32
}

enum ReleasePlan {
    static func commands(for version: ReleaseVersion, developerDir: String, key: APIKey?) -> [Command] {
        let tag = "\(version.marketing)-\(version.build)"
        let archive = ".build/distribution/pray.daily-\(tag).xcarchive"
        let xcode = ["DEVELOPER_DIR": developerDir]
        let auth = key.map { ["-authenticationKeyPath", $0.path, "-authenticationKeyID", $0.id, "-authenticationKeyIssuerID", $0.issuer] } ?? []
        return [
            Command(name: "xcodegen", tool: "xcodegen", arguments: ["generate", "--spec", VersionFiles.projectPath], log: ".build/ios-\(tag)-xcodegen.log"),
            Command(name: "archive", tool: "xcodebuild", arguments: [
                "-project", "Assets/ios/PrayDaily.xcodeproj", "-scheme", "pray.daily", "-configuration", "Release",
                "-destination", "generic/platform=iOS", "-archivePath", archive, "-allowProvisioningUpdates",
            ] + auth + ["archive"], environment: xcode, log: ".build/ios-\(tag)-archive.log"),
            Command(name: "upload", tool: "xcodebuild", arguments: [
                "-exportArchive", "-archivePath", archive, "-exportOptionsPlist", "Assets/ios/UploadOptions.plist",
                "-exportPath", ".build/distribution/TestFlight-\(tag)", "-allowProvisioningUpdates",
            ] + auth, environment: xcode, log: ".build/ios-\(tag)-upload.log"),
        ]
    }
}

// MARK: - App Store Connect

struct APIKey {
    var id: String
    var issuer: String
    var path: String
    var privateKey: P256.Signing.PrivateKey

    init(id: String, issuer: String, pem: String, path: String) throws {
        guard let privateKey = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { throw ReleaseError.badKey("\(path) is not an ES256 .p8 private key") }
        self.id = id
        self.issuer = issuer
        self.path = path
        self.privateKey = privateKey
    }

    static func load(id: String, issuer: String, path: String) throws -> APIKey {
        guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else { throw ReleaseError.badKey("cannot read \(path)") }
        return try APIKey(id: id, issuer: issuer, pem: pem, path: path)
    }

    /// ES256 JWT for the App Store Connect API; Apple rejects tokens that live longer than 20 minutes.
    func token(now: Date) throws -> String {
        let issued = Int(now.timeIntervalSince1970)
        let header: [String: Any] = ["alg": "ES256", "kid": id, "typ": "JWT"]
        let payload: [String: Any] = ["iss": issuer, "iat": issued, "exp": issued + 1200, "aud": "appstoreconnect-v1"]
        let input = try [header, payload].map { base64URL(try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys)) }.joined(separator: ".")
        return input + "." + base64URL(try privateKey.signature(for: Data(input.utf8)).rawRepresentation)
    }
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

struct HTTPResponse {
    var status: Int
    var body: Data
}

protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}

struct Build: Equatable {
    var id: String
    var version: String
    var state: String
}

struct BetaGroup: Equatable {
    var id: String
    var name: String
    var isInternal: Bool
    var hasAccessToAllBuilds: Bool
}

enum InviteOutcome: Equatable {
    case invited, addedAndInvited, alreadyInGroup
}

final class AppStoreConnect {
    static let host = "https://api.appstoreconnect.apple.com"
    let key: APIKey
    let transport: HTTPTransport
    let now: () -> Date

    init(key: APIKey, transport: HTTPTransport = URLSessionTransport(), now: @escaping () -> Date = Date.init) {
        self.key = key
        self.transport = transport
        self.now = now
    }

    func latestBuildNumber(app: String) async throws -> Int? {
        try await list("/v1/builds", [("filter[app]", app), ("sort", "-uploadedDate"), ("fields[builds]", "version"), ("limit", "200")])
            .compactMap { ($0.attributes["version"] as? String).flatMap(Int.init) }.max()
    }

    func build(app: String, version: ReleaseVersion) async throws -> Build? {
        try await list("/v1/builds", [
            ("filter[app]", app), ("filter[version]", String(version.build)),
            ("filter[preReleaseVersion.version]", version.marketing), ("fields[builds]", "version,processingState"), ("limit", "1"),
        ]).first.map { Build(id: $0.id, version: $0.attributes["version"] as? String ?? "", state: $0.attributes["processingState"] as? String ?? "") }
    }

    func group(named name: String, app: String) async throws -> BetaGroup {
        let groups = try await list("/v1/betaGroups", [("filter[app]", app), ("filter[name]", name), ("fields[betaGroups]", "name,isInternalGroup,hasAccessToAllBuilds")])
        // filter[name] can match loosely, so insist on the exact name.
        guard let match = groups.first(where: { $0.attributes["name"] as? String == name }) else { throw ReleaseError.groupNotFound(name) }
        return BetaGroup(id: match.id, name: name, isInternal: match.attributes["isInternalGroup"] as? Bool ?? false, hasAccessToAllBuilds: match.attributes["hasAccessToAllBuilds"] as? Bool ?? false)
    }

    func addBuild(_ build: Build, to group: BetaGroup) async throws {
        try await send("POST", "/v1/betaGroups/\(group.id)/relationships/builds", json: ["data": [["type": "builds", "id": build.id]]])
    }

    /// Creating a tester inside a group makes Apple send the invitation email; a tester who already
    /// exists in another group is linked to this one and invited explicitly.
    func invite(_ email: String, to group: BetaGroup, app: String) async throws -> InviteOutcome {
        let inGroup = try await list("/v1/betaTesters", [("filter[email]", email), ("filter[betaGroups]", group.id), ("fields[betaTesters]", "email"), ("limit", "1")])
        if !inGroup.isEmpty { return .alreadyInGroup }
        if let tester = try await list("/v1/betaTesters", [("filter[email]", email), ("fields[betaTesters]", "email"), ("limit", "1")]).first {
            try await send("POST", "/v1/betaGroups/\(group.id)/relationships/betaTesters", json: ["data": [["type": "betaTesters", "id": tester.id]]])
            try await send("POST", "/v1/betaTesterInvitations", json: ["data": ["type": "betaTesterInvitations", "relationships": [
                "app": ["data": ["type": "apps", "id": app]],
                "betaTester": ["data": ["type": "betaTesters", "id": tester.id]],
            ]]])
            return .addedAndInvited
        }
        do {
            try await send("POST", "/v1/betaTesters", json: ["data": ["type": "betaTesters", "attributes": ["email": email], "relationships": [
                "betaGroups": ["data": [["type": "betaGroups", "id": group.id]]],
            ]]])
        } catch let ReleaseError.api(status, method, path, detail) where group.isInternal {
            throw ReleaseError.api(status: status, method: method, path: path, detail: detail + " (internal groups only accept App Store Connect users; add them under Users and Access first, or use an external group)")
        }
        return .invited
    }

    private func list(_ path: String, _ query: [(String, String)]) async throws -> [(id: String, attributes: [String: Any])] {
        let body = try await send("GET", path, query: query)
        let items = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return items.compactMap { item in (item["id"] as? String).map { ($0, item["attributes"] as? [String: Any] ?? [:]) } }
    }

    @discardableResult
    private func send(_ method: String, _ path: String, query: [(String, String)] = [], json: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.host + path + Self.encode(query))!)
        request.httpMethod = method
        request.setValue("Bearer \(try key.token(now: now()))", forHTTPHeaderField: "Authorization")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw ReleaseError.api(status: response.status, method: method, path: path, detail: Self.detail(response.body)) }
        return response.body
    }

    /// `+` must be escaped: the server reads a literal `+` in a query as a space, which breaks `name+tag@` emails.
    static func encode(_ query: [(String, String)]) -> String {
        guard !query.isEmpty else { return "" }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return "?" + query.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&")
    }

    static func detail(_ body: Data) -> String {
        let errors = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["errors"] as? [[String: Any]] ?? []
        let text = errors.compactMap { $0["detail"] as? String ?? $0["title"] as? String }.joined(separator: "; ")
        return text.isEmpty ? String(decoding: body.prefix(300), as: UTF8.self) : text
    }
}

// MARK: - Pipeline

enum Invites {
    /// Splits comma lists, lowercases, drops duplicates and rejects anything that isn't an address.
    static func normalize(_ raw: [String]) throws -> [String] {
        var seen = Set<String>(), emails: [String] = []
        for value in raw.flatMap({ $0.split(separator: ",") }) {
            let email = value.trimmingCharacters(in: .whitespaces).lowercased()
            let parts = email.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
                  !email.contains(where: \.isWhitespace) else { throw ReleaseError.invalidEmail(String(value)) }
            if seen.insert(email).inserted { emails.append(email) }
        }
        return emails
    }

    static func send(_ emails: [String], group: BetaGroup, app: String, connect: AppStoreConnect, say: (String) -> Void) async throws -> [String: InviteOutcome] {
        var outcomes: [String: InviteOutcome] = [:]
        for email in emails {
            let outcome = try await connect.invite(email, to: group, app: app)
            outcomes[email] = outcome
            switch outcome {
            case .invited: say("Invited \(email) to \(group.name)")
            case .addedAndInvited: say("Added existing tester \(email) to \(group.name) and re-sent the invitation")
            case .alreadyInGroup: say("\(email) is already in \(group.name)")
            }
        }
        return outcomes
    }
}

struct Release {
    var root: URL
    var developerDir: String
    var app: String
    var group: String?
    var invite: [String] = []
    var dryRun = false
    var connect: AppStoreConnect?
    var runner: CommandRunning
    var sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0 * 1_000_000_000) }
    var pollSeconds: UInt64 = 30
    var polls = 120
    var say: (String) -> Void = { print($0) }

    /// Everything that can be checked without building runs first, so a bad email or a reused
    /// build number fails in seconds instead of after a ten-minute archive.
    @discardableResult
    func run() async throws -> ReleaseVersion {
        let version = try VersionFiles.read(root: root)
        let emails = try Invites.normalize(invite)
        if !emails.isEmpty && group == nil { throw ReleaseError.groupRequired }
        if connect == nil && group != nil { throw ReleaseError.credentialsRequired("Adding the build to a group or inviting testers") }
        var betaGroup: BetaGroup?
        if let connect {
            if let latest = try await connect.latestBuildNumber(app: app), version.build <= latest {
                throw ReleaseError.buildNumberUsed(version, latest: latest)
            }
            if let group { betaGroup = try await connect.group(named: group, app: app) }
        }
        say("\(dryRun ? "Planning" : "Releasing") pray.daily \(version) with \(developerDir)")
        for command in ReleasePlan.commands(for: version, developerDir: developerDir, key: connect?.key) {
            if dryRun {
                say("  \(command.environment.map { "\($0)=\($1) " }.joined())\(([command.tool] + command.arguments).joined(separator: " "))")
                continue
            }
            say("→ \(command.name) (log: \(command.log))")
            let status = try runner.run(command)
            guard status == 0 else { throw ReleaseError.commandFailed(command.name, status: status, log: command.log) }
        }
        guard !dryRun else { return version }
        guard let connect else {
            say("Uploaded \(version). Set ASC_KEY_ID and ASC_ISSUER_ID to wait for processing and invite testers.")
            return version
        }
        let build = try await processed(version, connect: connect)
        say("App Store Connect finished processing \(version)")
        if let betaGroup {
            if betaGroup.isInternal && betaGroup.hasAccessToAllBuilds {
                say("\(betaGroup.name) already receives every build")
            } else {
                try await connect.addBuild(build, to: betaGroup)
                say("Added \(version) to \(betaGroup.name)")
            }
            if !betaGroup.isInternal { say("\(betaGroup.name) is external: the build needs Beta App Review before testers can install it") }
            _ = try await Invites.send(emails, group: betaGroup, app: app, connect: connect, say: say)
        }
        return version
    }

    private func processed(_ version: ReleaseVersion, connect: AppStoreConnect) async throws -> Build {
        for attempt in 0..<polls {
            if let build = try await connect.build(app: app, version: version) {
                if build.state == "VALID" { return build }
                if build.state == "FAILED" || build.state == "INVALID" { throw ReleaseError.buildRejected(version, state: build.state) }
            }
            if attempt == 0 { say("Waiting for App Store Connect to process \(version)…") }
            try await sleep(pollSeconds)
        }
        throw ReleaseError.buildNotProcessed(version)
    }
}
