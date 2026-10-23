import Foundation

// Usage (via ./testflight.sh):
//   release [--group NAME] [--invite EMAIL[,EMAIL...]]... [--dry-run]
//   invite --group NAME EMAIL...
// Credentials: ASC_KEY_ID, ASC_ISSUER_ID, optional ASC_KEY_PATH
// (default ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8). ASC_APP_ID defaults to pray.daily's app.

struct ProcessRunner: CommandRunning {
    var root: URL

    func run(_ command: Command) throws -> Int32 {
        let log = root.appendingPathComponent(command.log)
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command.tool] + command.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { $1 }
        process.currentDirectoryURL = root
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

@main struct TestFlightCLI {
    static let usage = """
    usage: testflight.sh release [--group NAME] [--invite EMAIL[,EMAIL...]]... [--dry-run]
           testflight.sh invite --group NAME EMAIL...
    """

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch let error as ReleaseError {
            fail(error.description)
        } catch {
            fail("\(error)")
        }
    }

    static func run(_ arguments: [String]) async throws {
        guard let mode = arguments.first, mode == "release" || mode == "invite" else { fail(usage) }
        var group: String?, emails: [String] = [], dryRun = false
        var rest = arguments.dropFirst()
        while let argument = rest.popFirst() {
            switch argument {
            case "--group": group = rest.popFirst() ?? { fail(usage) }()
            case "--invite": emails.append(rest.popFirst() ?? { fail(usage) }())
            case "--dry-run": dryRun = true
            case _ where mode == "invite" && !argument.hasPrefix("-"): emails.append(argument)
            default: fail(usage)
            }
        }
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = environment["ASC_APP_ID"] ?? "6816553437"
        let connect = try connection(environment)

        if mode == "invite" {
            guard let group else { throw ReleaseError.groupRequired }
            guard let connect else { throw ReleaseError.credentialsRequired("Inviting testers") }
            let addresses = try Invites.normalize(emails)
            guard !addresses.isEmpty else { fail(usage) }
            let betaGroup = try await connect.group(named: group, app: app)
            _ = try await Invites.send(addresses, group: betaGroup, app: app, connect: connect) { print($0) }
            return
        }
        let release = Release(root: root, developerDir: try developerDir(environment, root: root), app: app, group: group,
                              invite: emails, dryRun: dryRun, connect: connect, runner: ProcessRunner(root: root))
        try await release.run()
    }

    static func connection(_ environment: [String: String]) throws -> AppStoreConnect? {
        guard let id = environment["ASC_KEY_ID"], let issuer = environment["ASC_ISSUER_ID"] else { return nil }
        let path = environment["ASC_KEY_PATH"] ?? NSString(string: "~/.appstoreconnect/private_keys/AuthKey_\(id).p8").expandingTildeInPath
        return AppStoreConnect(key: try APIKey.load(id: id, issuer: issuer, path: path))
    }

    /// DEVELOPER_DIR wins; otherwise the TestFlight-accepted toolchain under .build. Never touches xcode-select.
    static func developerDir(_ environment: [String: String], root: URL) throws -> String {
        if let dir = environment["DEVELOPER_DIR"] { return dir }
        let local = root.appendingPathComponent(".build/toolchains/xcode-27.1/Xcode.app/Contents/Developer").path
        guard FileManager.default.fileExists(atPath: local) else { fail("Set DEVELOPER_DIR to an Xcode that App Store Connect accepts") }
        return local
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
