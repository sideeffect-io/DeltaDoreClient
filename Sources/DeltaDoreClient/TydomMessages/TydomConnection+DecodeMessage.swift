import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension TydomConnection {
    func decodedMessages(using decoder: TydomMessageDecoder) -> AsyncMapSequence<AsyncStream<Data>, TydomMessage> {
        messages().map { data in
            await decoder.decode(data)
        }
    }
}
