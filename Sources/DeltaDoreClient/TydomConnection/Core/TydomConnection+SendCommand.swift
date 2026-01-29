import Foundation

extension TydomConnection {
    func send(_ command: TydomCommand) async throws {
        try await send(text: command.request)
    }
}
