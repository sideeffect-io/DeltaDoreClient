import Foundation

actor TydomPongStore {
    private var lastPongAt: Date?

    init() {}

    func markPongReceived(at date: Date = Date()) {
        lastPongAt = date
    }

    func lastReceivedAt() -> Date? {
        lastPongAt
    }
}
