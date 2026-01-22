import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension TydomConnection {
    func send(_ command: TydomCommand) async throws {
        try await send(text: command.request)
    }
}
