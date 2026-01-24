import Foundation

actor TydomCDataReplyStore {
    struct Reply: Sendable, Equatable {
        let transactionId: String
        let events: [JSONValue]
        let done: Bool
    }

    private var replies: [String: Reply] = [:]

    init() {}

    func append(_ chunk: TydomCDataReplyChunk) {
        let current = replies[chunk.transactionId]
        let mergedEvents = (current?.events ?? []) + chunk.events
        let done = current?.done == true || chunk.done
        replies[chunk.transactionId] = Reply(
            transactionId: chunk.transactionId,
            events: mergedEvents,
            done: done
        )
    }

    func reply(for transactionId: String) -> Reply? {
        replies[transactionId]
    }

    func takeReplyIfDone(for transactionId: String) -> Reply? {
        guard let reply = replies[transactionId], reply.done else { return nil }
        replies.removeValue(forKey: transactionId)
        return reply
    }

    func clear(transactionId: String) {
        replies.removeValue(forKey: transactionId)
    }
}
