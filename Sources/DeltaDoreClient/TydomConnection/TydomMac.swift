import Foundation

public struct TydomMac: Sendable, Equatable {
    let value: String

    public init(_ value: String) {
        self.value = TydomMac.normalize(value)
    }

    public static func normalize(_ mac: String) -> String {
        mac.filter { $0.isHexDigit }.uppercased()
    }

    public static func colonize(_ normalized: String) -> String? {
        guard normalized.count == 12 else { return nil }
        var parts: [String] = []
        var index = normalized.startIndex
        for _ in 0..<6 {
            let nextIndex = normalized.index(index, offsetBy: 2)
            parts.append(String(normalized[index..<nextIndex]))
            index = nextIndex
        }
        return parts.joined(separator: ":")
    }
}
