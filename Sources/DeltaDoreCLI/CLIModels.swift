import Foundation
import DeltaDoreClient

enum StartupAction: Sendable {
    case run(CLIOptions)
    case runAuto(AutoOptions)
    case runResolved(ResolveOptions)
    case help(String)
    case failure(String)
}

struct CLIOptions: Sendable {
    let configuration: TydomConnection.Configuration
    let onDisconnect: (@Sendable () async -> Void)?
}

struct AutoOptions: Sendable {
    let mac: String?
    let cloudCredentials: TydomConnection.CloudCredentials?
    let siteIndex: Int?
    let bonjourServices: [String]
    let timeout: TimeInterval
    let pollInterval: Int
    let pollOnlyActive: Bool
    let allowInsecureTLS: Bool?
    let remoteHost: String?
    let listSites: Bool
    let forceRemote: Bool
    let dumpSitesResponse: Bool
    let resetSite: Bool
}

struct ResolveOptions: Sendable {
    let mode: String
    let host: String?
    let mac: String?
    let password: String?
    let cloudCredentials: TydomConnection.CloudCredentials?
    let siteIndex: Int?
    let listSites: Bool
    let resetSite: Bool
    let timeout: TimeInterval
    let pollInterval: Int
    let pollOnlyActive: Bool
    let allowInsecureTLS: Bool?
    let dumpSitesResponse: Bool
    let bonjourServices: [String]
}

enum CLICommand: Sendable {
    case help
    case quit
    case setActive(Bool)
    case send(TydomCommand)
    case sendMany([TydomCommand])
    case sendRaw(String)
}

struct CLIParseError: Error, Sendable {
    let message: String
}

actor ConsoleWriter {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func writeLine(_ line: String) {
        write(line + "\n")
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}
