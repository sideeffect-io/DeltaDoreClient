import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension TydomConnection {
    struct CloudCredentials: Sendable {
        let email: String
        let password: String

        init(email: String, password: String) {
            self.email = email
            self.password = password
        }
    }
}
