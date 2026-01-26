import Foundation

extension TydomConnection.Configuration.Mode: Equatable {
    public static func == (
        lhs: TydomConnection.Configuration.Mode,
        rhs: TydomConnection.Configuration.Mode
    ) -> Bool {
        switch (lhs, rhs) {
        case (.local(let lhsHost), .local(let rhsHost)):
            return lhsHost == rhsHost
        case (.remote(let lhsHost), .remote(let rhsHost)):
            return lhsHost == rhsHost
        default:
            return false
        }
    }
}
