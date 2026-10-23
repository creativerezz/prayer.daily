import CryptoKit
import Foundation

private let testNow = ISO8601DateFormatter().date(from: "2026-10-22T08:00:00Z")!
private let signingKey = P256.Signing.PrivateKey()
private let apiKey = try! APIKey(id: "KEY123", issuer: "issuer-0000", pem: signingKey.pemRepresentation, path: "/keys/AuthKey_KEY123.p8")
private let developerDir = "/Toolchains/Xcode-27.1.app/Contents/Developer"

/// In-memory App Store Connect: keeps builds, groups and testers so tests assert outcomes, and records
/// every request (plus the runner's commands) on one timeline so tests can assert ordering.
private final class FakeConnect: HTTPTransport {
    final class FakeBuild { var id: String; var marketing: String; var version: String; var states: [String]
        init(id: String, marketing: String, version: String, states: [String]) { (self.id, self.marketing, self.version, self.states) = (id, marketing, version, states) }
    }
    struct Tester { var id: String; var email: String; var groups: Set<String> }
    var builds: [FakeBuild] = []
    var groups: [BetaGroup] = [BetaGroup(id: "g1", name: "Personal testing", isInternal: true, hasAccessToAllBuilds: false)]
    var testers: [Tester] = []
    var groupBuilds: [String: [String]] = [:]
    var emailed: [String] = []
    var timeline: [String] = []
    var authorizations: [String] = []
    var failCreate: (status: Int, detail: String)?
    /// Processing states the build reports, one per poll, once the upload succeeds.
    var uploadStates = ["PROCESSING", "PROCESSING", "VALID"]

    func addBuild(_ version: String, marketing: String = "0.1.0", states: [String] = ["VALID"]) {
        builds.append(FakeBuild(id: "b\(version)", marketing: marketing, version: version, states: states))
    }
    var writes: [String] { timeline.filter { $0.hasPrefix("POST") } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = request.httpMethod ?? "GET", url = request.url!, query = Self.query(url)
        let parts = url.path.split(separator: "/").map(String.init)
        timeline.append("\(method) \(url.path)")
        authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let data = body["data"] as? [String: Any]
        let links = (body["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []

        switch (method, parts) {
        case ("GET", ["v1", "builds"]):
            check(query["filter[app]"] == "6816553437", "Builds queried for the wrong app")
            let matches = builds.filter { build in
                query["filter[version]"].map { $0 == build.version } ?? true && query["filter[preReleaseVersion.version]"].map { $0 == build.marketing } ?? true
            }
            return Self.list(matches.map { build in
                let state = build.states.count > 1 ? build.states.removeFirst() : build.states[0]
                return ["id": build.id, "attributes": ["version": build.version, "processingState": state]]
            })
        case ("GET", ["v1", "betaGroups"]):
            return Self.list(groups.filter { $0.name.contains(query["filter[name]"] ?? "") }.map {
                ["id": $0.id, "attributes": ["name": $0.name, "isInternalGroup": $0.isInternal, "hasAccessToAllBuilds": $0.hasAccessToAllBuilds]]
            })
        case ("GET", ["v1", "betaTesters"]):
            return Self.list(testers.filter { $0.email == query["filter[email]"] && (query["filter[betaGroups]"].map($0.groups.contains) ?? true) }
                .map { ["id": $0.id, "attributes": ["email": $0.email]] })
        case ("POST", ["v1", "betaTesters"]):
            if let failCreate { return Self.error(failCreate.status, failCreate.detail) }
            let email = (data?["attributes"] as? [String: Any])?["email"] as! String
            let groupLinks = (((data?["relationships"] as? [String: Any])?["betaGroups"] as? [String: Any])?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
            testers.append(Tester(id: "t\(testers.count + 1)", email: email, groups: Set(groupLinks)))
            emailed.append(email)
            return HTTPResponse(status: 201, body: Data("{}".utf8))
        case ("POST", _) where parts.count == 5 && parts[1] == "betaGroups" && parts[4] == "betaTesters":
            let group = parts[2]
            for id in links { testers[testers.firstIndex { $0.id == id }!].groups.insert(group) }
            return HTTPResponse(status: 204, body: Data())
        case ("POST", _) where parts.count == 5 && parts[1] == "betaGroups" && parts[4] == "builds":
            let group = parts[2]
            groupBuilds[group, default: []] += links
            return HTTPResponse(status: 204, body: Data())
        case ("POST", ["v1", "betaTesterInvitations"]):
            let relationships = data?["relationships"] as? [String: Any]
            let app = ((relationships?["app"] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String
            let tester = ((relationships?["betaTester"] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String
            check(app == "6816553437", "Invitation for the wrong app")
            emailed.append(testers.first { $0.id == tester }!.email)
            return HTTPResponse(status: 201, body: Data("{}".utf8))
        default:
            return Self.error(404, "No fake route for \(method) \(url.path)")
        }
    }

    /// Decodes like the real server: a literal `+` in a query is a space.
    static func query(_ url: URL) -> [String: String] {
        var result: [String: String] = [:]
        for pair in (url.query(percentEncoded: true) ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" }
            result[kv[0]] = kv.count > 1 ? kv[1] : ""
        }
        return result
    }
    static func list(_ items: [[String: Any]]) -> HTTPResponse {
        HTTPResponse(status: 200, body: try! JSONSerialization.data(withJSONObject: ["data": items]))
    }
    static func error(_ status: Int, _ detail: String) -> HTTPResponse {
        HTTPResponse(status: status, body: try! JSONSerialization.data(withJSONObject: ["errors": [["status": String(status), "detail": detail]]]))
    }
}

private final class FakeRunner: CommandRunning {
    var commands: [Command] = []
    var status: [String: Int32] = [:]
    var onRun: ((Command) -> Void)?
    func run(_ command: Command) throws -> Int32 {
        commands.append(command)
        onRun?(command)
        return status[command.name] ?? 0
    }
}

private final class Recorder {
    var lines: [String] = []
    var sleeps = 0
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    precondition(condition(), message, file: file, line: line)
}

@main struct TestFlightTests {
    static var passed = 0
    static var roots: [URL] = []

    static func test(_ name: String, _ body: () async throws -> Void) async throws {
        try await body()
        passed += 1
        print("PASS: \(name)")
    }
    static func expect(_ expected: ReleaseError, file: StaticString = #file, line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            check(false, "Expected \(expected), got success", file: file, line: line)
        } catch let error as ReleaseError {
            check(error == expected, "Expected \(expected), got \(error)", file: file, line: line)
        } catch {
            check(false, "Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    /// Throwaway repo root holding just the two version files the release reads.
    static func fixtureRoot(marketing: String = "0.1.0", build: Int = 5, plistBuild: Int? = nil) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pray.daily.testflight.\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("Assets/ios"), withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try! "settings:\n  base:\n    MARKETING_VERSION: \(marketing)\n    CURRENT_PROJECT_VERSION: \(build)\n"
            .write(to: root.appendingPathComponent(VersionFiles.projectPath), atomically: true, encoding: .utf8)
        try! PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": marketing, "CFBundleVersion": String(plistBuild ?? build)], format: .xml, options: 0)
            .write(to: root.appendingPathComponent(VersionFiles.plistPath))
        roots.append(root)
        return root
    }

    private static func makeRelease(_ root: URL, server: FakeConnect?, runner: FakeRunner, recorder: Recorder = Recorder(),
                                    group: String? = "Personal testing", invite: [String] = []) -> Release {
        var release = Release(root: root, developerDir: developerDir, app: "6816553437", group: group, invite: invite,
                              connect: server.map { AppStoreConnect(key: apiKey, transport: $0, now: { testNow }) }, runner: runner)
        release.sleep = { _ in recorder.sleeps += 1 }
        release.polls = 5
        release.say = { recorder.lines.append($0) }
        // Mirror the real pipeline: a successful upload makes the build appear on App Store Connect.
        if let server {
            runner.onRun = { command in
                server.timeline.append("run \(command.name)")
                if command.name == "upload" && runner.status["upload", default: 0] == 0 { server.addBuild("5", states: server.uploadStates) }
            }
        }
        return release
    }

    static func main() async {
        do {
            try await run()
        } catch {
            check(false, "Unexpected error: \(error)")
        }
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    static func run() async throws {
        try await test("repo project.yml and Info.plist agree on version and build") {
            let version = try VersionFiles.read(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            check(version.build > 0, "Repo build number missing")
        }

        try await test("mismatched or malformed version files are rejected") {
            await expect(.versionMismatch(ios: ReleaseVersion(marketing: "0.1.0", build: 5), mac: ReleaseVersion(marketing: "0.1.0", build: 4))) {
                _ = try VersionFiles.read(root: fixtureRoot(build: 5, plistBuild: 4))
            }
            await expect(.invalidMarketingVersion("0.1.0-beta")) { _ = try VersionFiles.project("MARKETING_VERSION: 0.1.0-beta\nCURRENT_PROJECT_VERSION: 5") }
            await expect(.missingSetting("CURRENT_PROJECT_VERSION", file: VersionFiles.projectPath)) { _ = try VersionFiles.project("MARKETING_VERSION: '0.1.0'") }
        }

        try await test("API token is a short-lived ES256 JWT signed by the key") {
            let parts = try apiKey.token(now: testNow).split(separator: ".").map(String.init)
            check(parts.count == 3, "JWT needs three parts")
            func decode(_ text: String) -> Data {
                var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
                return Data(base64Encoded: base64)!
            }
            let header = try JSONSerialization.jsonObject(with: decode(parts[0])) as! [String: Any]
            let payload = try JSONSerialization.jsonObject(with: decode(parts[1])) as! [String: Any]
            check(header["alg"] as? String == "ES256" && header["kid"] as? String == "KEY123", "JWT header")
            check(payload["iss"] as? String == "issuer-0000" && payload["aud"] as? String == "appstoreconnect-v1", "JWT claims")
            let issued = payload["iat"] as! Int, expires = payload["exp"] as! Int
            check(issued == Int(testNow.timeIntervalSince1970) && expires > issued && expires - issued <= 1200, "Apple rejects tokens over 20 minutes")
            let signature = try P256.Signing.ECDSASignature(rawRepresentation: decode(parts[2]))
            check(signingKey.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)), "JWT signature does not verify")
        }

        try await test("release builds, uploads, waits for processing, adds the build and invites new testers") {
            let server = FakeConnect(), runner = FakeRunner(), recorder = Recorder()
            server.addBuild("3"); server.addBuild("4")
            server.groups.append(BetaGroup(id: "g2", name: "Family", isInternal: false, hasAccessToAllBuilds: false))
            server.testers = [.init(id: "t-old", email: "old@example.com", groups: ["g1"]), .init(id: "t-family", email: "elsewhere@example.com", groups: ["g2"])]
            let release = makeRelease(fixtureRoot(), server: server, runner: runner, recorder: recorder,
                                      invite: [" New@Example.com, elsewhere@example.com", "old@example.com", "new@example.com"])
            let version = try await release.run()

            check(version == ReleaseVersion(marketing: "0.1.0", build: 5), "Released the wrong version")
            check(runner.commands.map(\.name) == ["xcodegen", "archive", "upload"], "Wrong command sequence: \(runner.commands.map(\.name))")
            let (archive, upload) = (runner.commands[1], runner.commands[2])
            let archivePath = ".build/distribution/pray.daily-0.1.0-5.xcarchive"
            check(archive.tool == "xcodebuild" && archive.arguments.last == "archive" && archive.arguments.contains(archivePath), "Archive command")
            check(archive.arguments.contains("generic/platform=iOS") && archive.arguments.contains("Release"), "Archive must be a Release device build")
            check(upload.arguments.starts(with: ["-exportArchive", "-archivePath", archivePath]) && upload.arguments.contains("Assets/ios/UploadOptions.plist"), "Upload must export that archive with UploadOptions.plist")
            for command in [archive, upload] {
                check(command.environment == ["DEVELOPER_DIR": developerDir], "Xcode is selected per command via DEVELOPER_DIR")
                check(command.arguments.contains("-authenticationKeyID") && command.arguments.contains(apiKey.path), "xcodebuild should use the API key")
            }
            check(archive.log == ".build/ios-0.1.0-5-archive.log" && upload.log == ".build/ios-0.1.0-5-upload.log", "Logs follow the .build/ios-<version>-<build> naming")

            check(recorder.sleeps == 2, "Should poll until VALID: slept \(recorder.sleeps)")
            check(server.groupBuilds == ["g1": ["b5"]], "Build not added to the group: \(server.groupBuilds)")
            check(server.emailed == ["new@example.com", "elsewhere@example.com"], "Wrong people emailed: \(server.emailed)")
            check(server.testers.first { $0.email == "new@example.com" }?.groups == ["g1"], "New tester not in the group")
            check(server.testers.first { $0.email == "elsewhere@example.com" }?.groups == ["g1", "g2"], "Existing tester not linked to the group")
            check(server.testers.count == 3, "Duplicate or case-variant emails created extra testers")
            check(recorder.lines.contains("old@example.com is already in Personal testing"), "Existing member should be reported, not re-invited")

            let timeline = server.timeline
            let firstCommand = timeline.firstIndex(of: "run xcodegen")!, uploaded = timeline.firstIndex(of: "run upload")!
            check(timeline[..<firstCommand].contains("GET /v1/builds") && timeline[..<firstCommand].contains("GET /v1/betaGroups"), "Build number and group must be checked before building")
            check(timeline.firstIndex(of: "POST /v1/betaGroups/g1/relationships/builds")! > uploaded, "Build added to the group before it was uploaded")
            check(server.writes.allSatisfy { timeline.firstIndex(of: $0)! > uploaded }, "Nothing may be written to App Store Connect before the upload")
            check(server.authorizations.allSatisfy { $0.hasPrefix("Bearer ey") }, "Every API request needs a JWT")
        }

        try await test("a build number App Store Connect already has fails before building") {
            let server = FakeConnect(), runner = FakeRunner()
            server.addBuild("4"); server.addBuild("5", marketing: "0.0.9")
            await expect(.buildNumberUsed(ReleaseVersion(marketing: "0.1.0", build: 5), latest: 5)) {
                try await makeRelease(fixtureRoot(), server: server, runner: runner).run()
            }
            check(runner.commands.isEmpty, "Built despite a reused build number")
        }

        try await test("bad invites, unknown groups and missing credentials fail before building") {
            let server = FakeConnect(), runner = FakeRunner()
            await expect(.invalidEmail("not-an-email")) { try await makeRelease(fixtureRoot(), server: server, runner: runner, invite: ["ok@example.com,not-an-email"]).run() }
            check(server.timeline.isEmpty, "Contacted App Store Connect before validating emails")
            await expect(.groupRequired) { try await makeRelease(fixtureRoot(), server: server, runner: runner, group: nil, invite: ["ok@example.com"]).run() }
            await expect(.groupNotFound("Personal")) { try await makeRelease(fixtureRoot(), server: server, runner: runner, group: "Personal").run() }
            await expect(.credentialsRequired("Adding the build to a group or inviting testers")) { try await makeRelease(fixtureRoot(), server: nil, runner: runner).run() }
            check(runner.commands.isEmpty, "Built despite a preflight failure")
        }

        try await test("a failed archive stops before upload and distributes nothing") {
            let server = FakeConnect(), runner = FakeRunner()
            runner.status["archive"] = 65
            await expect(.commandFailed("archive", status: 65, log: ".build/ios-0.1.0-5-archive.log")) {
                try await makeRelease(fixtureRoot(), server: server, runner: runner, invite: ["new@example.com"]).run()
            }
            check(runner.commands.map(\.name) == ["xcodegen", "archive"], "Uploaded after a failed archive")
            check(server.writes.isEmpty && server.emailed.isEmpty, "Invited testers after a failed archive")
        }


        try await test("a rejected or stuck build is reported and nobody is invited") {
            let rejected = FakeConnect()
            rejected.uploadStates = ["PROCESSING", "INVALID"]
            await expect(.buildRejected(ReleaseVersion(marketing: "0.1.0", build: 5), state: "INVALID")) {
                try await makeRelease(fixtureRoot(), server: rejected, runner: FakeRunner(), invite: ["new@example.com"]).run()
            }
            check(rejected.writes.isEmpty && rejected.emailed.isEmpty, "Distributed a rejected build")
            let stuck = FakeConnect(), recorder = Recorder()
            stuck.uploadStates = ["PROCESSING"]
            await expect(.buildNotProcessed(ReleaseVersion(marketing: "0.1.0", build: 5))) {
                try await makeRelease(fixtureRoot(), server: stuck, runner: FakeRunner(), recorder: recorder, invite: ["new@example.com"]).run()
            }
            check(recorder.sleeps == 5 && stuck.writes.isEmpty, "Should give up after the poll budget without inviting")
        }

        try await test("groups that already get every build are not re-added; external groups warn about review") {
            let server = FakeConnect(), recorder = Recorder()
            server.groups = [BetaGroup(id: "g1", name: "Personal testing", isInternal: true, hasAccessToAllBuilds: true),
                             BetaGroup(id: "g9", name: "Friends", isInternal: false, hasAccessToAllBuilds: false)]
            try await makeRelease(fixtureRoot(), server: server, runner: FakeRunner(), recorder: recorder).run()
            check(server.groupBuilds.isEmpty && recorder.lines.contains("Personal testing already receives every build"), "Re-added a build to an all-builds group")
            let external = FakeConnect(), externalLog = Recorder()
            external.groups = server.groups
            try await makeRelease(fixtureRoot(), server: external, runner: FakeRunner(), recorder: externalLog, group: "Friends").run()
            check(external.groupBuilds == ["g9": ["b5"]], "Build not added to the external group")
            check(externalLog.lines.contains { $0.contains("Beta App Review") }, "External group should warn about Beta App Review")
        }

        try await test("invites escape plus addresses and explain internal-group rejections") {
            let server = FakeConnect()
            let connect = AppStoreConnect(key: apiKey, transport: server, now: { testNow })
            let group = try await connect.group(named: "Personal testing", app: "6816553437")
            let first = try await connect.invite("reza+beta@example.com", to: group, app: "6816553437")
            let again = try await connect.invite("reza+beta@example.com", to: group, app: "6816553437")
            check(first == .invited && again == .alreadyInGroup, "A '+' address must be found again, not recreated: \(first), \(again)")
            check(server.testers.map(\.email) == ["reza+beta@example.com"], "Tester email mangled: \(server.testers.map(\.email))")
            let encoded = AppStoreConnect.encode([("filter[email]", "a+b@x.com"), ("filter[name]", "Personal testing")])
            check(encoded.contains("=a%2Bb@x.com&") && encoded.hasSuffix("=Personal%20testing") && !encoded.contains("+"), "Query not escaped: \(encoded)")
            server.failCreate = (409, "The email is not a member of this team")
            do {
                _ = try await connect.invite("stranger@example.com", to: group, app: "6816553437")
                check(false, "Internal-group rejection was swallowed")
            } catch let ReleaseError.api(status, _, _, detail) {
                check(status == 409 && detail.contains("not a member") && detail.contains("Users and Access"), "Rejection lost Apple's detail or the hint: \(detail)")
            }
        }

        try await test("without credentials it only builds and uploads, using the Xcode account") {
            let runner = FakeRunner(), recorder = Recorder()
            try await makeRelease(fixtureRoot(), server: nil, runner: runner, recorder: recorder, group: nil).run()
            check(runner.commands.map(\.name) == ["xcodegen", "archive", "upload"], "Upload skipped without credentials")
            check(runner.commands.allSatisfy { !$0.arguments.contains("-authenticationKeyID") }, "Passed key flags without a key")
            check(recorder.lines.last?.contains("ASC_KEY_ID") == true, "Should say how to enable waiting and invites")
        }

        try await test("dry run checks App Store Connect but runs nothing") {
            let server = FakeConnect(), runner = FakeRunner(), recorder = Recorder()
            var release = makeRelease(fixtureRoot(), server: server, runner: runner, recorder: recorder, invite: ["new@example.com"])
            release.dryRun = true
            try await release.run()
            check(runner.commands.isEmpty && server.writes.isEmpty && server.emailed.isEmpty, "Dry run changed something")
            check(recorder.lines.contains { $0.contains("DEVELOPER_DIR=\(developerDir) xcodebuild -exportArchive") }, "Dry run should print the upload command")
        }

        print("PASS: \(passed) TestFlight tests")
        if CommandLine.arguments.contains("--live") { try await liveChecks() }
    }

    /// Read-only: never uploads, adds builds or invites anyone.
    static func liveChecks() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let id = environment["ASC_KEY_ID"], let issuer = environment["ASC_ISSUER_ID"] else {
            print("SKIP: live App Store Connect (set ASC_KEY_ID and ASC_ISSUER_ID)")
            return
        }
        let path = environment["ASC_KEY_PATH"] ?? NSString(string: "~/.appstoreconnect/private_keys/AuthKey_\(id).p8").expandingTildeInPath
        let connect = AppStoreConnect(key: try APIKey.load(id: id, issuer: issuer, path: path))
        let app = environment["ASC_APP_ID"] ?? "6816553437"
        let latest = try await connect.latestBuildNumber(app: app)
        check(latest != nil, "App Store Connect returned no builds for \(app)")
        let repo = try VersionFiles.read(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        print("PASS: live App Store Connect — latest build \(latest!), repo is \(repo)\(repo.build > latest! ? "" : " (bump CURRENT_PROJECT_VERSION before the next upload)")")
        if let name = environment["ASC_GROUP"] {
            let group = try await connect.group(named: name, app: app)
            print("PASS: live TestFlight group \(group.name) (\(group.isInternal ? "internal" : "external"))")
        }
    }
}
