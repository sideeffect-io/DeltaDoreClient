import Foundation
import Testing
@testable import DeltaDoreClient

@Test func pongStore_recordsLastPong() async {
    // Given
    let store = TydomPongStore()
    let now = Date()

    // When
    let initial = await store.lastReceivedAt()
    await store.markPongReceived(at: now)
    let updated = await store.lastReceivedAt()

    // Then
    #expect(initial == nil)
    #expect(updated == now)
}

@Test func cdataReplyStore_accumulatesAndClears() async {
    // Given
    let store = TydomCDataReplyStore()
    let chunk1 = TydomCDataReplyChunk(transactionId: "t1", events: [.string("a")], done: false)
    let chunk2 = TydomCDataReplyChunk(transactionId: "t1", events: [.string("b")], done: true)

    // When
    await store.append(chunk1)
    await store.append(chunk2)
    let reply = await store.reply(for: "t1")
    let doneReply = await store.takeReplyIfDone(for: "t1")
    let cleared = await store.reply(for: "t1")

    // Then
    #expect(reply?.events == [.string("a"), .string("b")])
    #expect(reply?.done == true)
    #expect(doneReply?.events == [.string("a"), .string("b")])
    #expect(cleared == nil)
}
