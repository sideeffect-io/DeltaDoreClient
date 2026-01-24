import Foundation

actor TydomAppActivityStore {
    private var isActive: Bool

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
    }

    func isAppActive() -> Bool {
        isActive
    }
}
