import CryptoKit
import Foundation

struct DigestChallenge: Sendable {
    let realm: String
    let nonce: String
    let qop: String?
    let opaque: String?
    let algorithm: String?

    static func parse(from header: String) throws -> DigestChallenge {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("digest ") else {
            throw TydomConnection.ConnectionError.invalidChallenge
        }
        let paramsString = String(trimmed.dropFirst("Digest ".count))
        let pairs = splitHeaderParameters(paramsString)
        var values: [String: String] = [:]
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            var value = parts[1]
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        guard let realm = values["realm"], let nonce = values["nonce"] else {
            throw TydomConnection.ConnectionError.invalidChallenge
        }
        return DigestChallenge(
            realm: realm,
            nonce: nonce,
            qop: values["qop"],
            opaque: values["opaque"],
            algorithm: values["algorithm"]
        )
    }
}

struct DigestAuthorizationBuilder {
    static func build(
        challenge: DigestChallenge,
        username: String,
        password: String,
        method: String,
        uri: String,
        randomBytes: @Sendable (Int) -> [UInt8]
    ) throws -> String {
        if let algorithm = challenge.algorithm, algorithm.uppercased() != "MD5" {
            throw TydomConnection.ConnectionError.unsupportedAlgorithm(algorithm)
        }

        let ha1 = md5Hex("\(username):\(challenge.realm):\(password)")
        let ha2 = md5Hex("\(method):\(uri)")

        let cnonce = randomBytes(16).hexString
        let nc = "00000001"

        let qop = try selectQop(from: challenge.qop)
        let response: String
        if let qop {
            response = md5Hex("\(ha1):\(challenge.nonce):\(nc):\(cnonce):\(qop):\(ha2)")
        } else {
            response = md5Hex("\(ha1):\(challenge.nonce):\(ha2)")
        }

        var parts: [String] = []
        parts.append("username=\"\(username)\"")
        parts.append("realm=\"\(challenge.realm)\"")
        parts.append("nonce=\"\(challenge.nonce)\"")
        parts.append("uri=\"\(uri)\"")
        parts.append("response=\"\(response)\"")

        if let algorithm = challenge.algorithm {
            parts.append("algorithm=\(algorithm)")
        }
        if let qop {
            parts.append("qop=\(qop)")
            parts.append("nc=\(nc)")
            parts.append("cnonce=\"\(cnonce)\"")
        }
        if let opaque = challenge.opaque {
            parts.append("opaque=\"\(opaque)\"")
        }

        return "Digest " + parts.joined(separator: ", ")
    }

    private static func selectQop(from value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        let options = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if options.contains("auth") {
            return "auth"
        }
        throw TydomConnection.ConnectionError.unsupportedQop(value)
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private func splitHeaderParameters(_ header: String) -> [String] {
    var result: [String] = []
    var current = ""
    var isInQuotes = false

    for char in header {
        if char == "\"" {
            isInQuotes.toggle()
            current.append(char)
            continue
        }
        if char == "," && !isInQuotes {
            result.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
            continue
        }
        current.append(char)
    }

    if !current.isEmpty {
        result.append(current.trimmingCharacters(in: .whitespaces))
    }

    return result
}

private extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
