import Foundation

public enum TydomHTTPFrame: Sendable, Equatable {
    case request(TydomHTTPRequest)
    case response(TydomHTTPResponse)

    public var uriOrigin: String? {
        switch self {
        case .request(let request):
            return request.path
        case .response(let response):
            return response.headerValue("uri-origin")
        }
    }

    public var transactionId: String? {
        switch self {
        case .request(let request):
            return request.headerValue("transac-id")
        case .response(let response):
            return response.headerValue("transac-id")
        }
    }

    public var body: Data? {
        switch self {
        case .request(let request):
            return request.body
        case .response(let response):
            return response.body
        }
    }

    public var headers: [String: String] {
        switch self {
        case .request(let request):
            return request.headers
        case .response(let response):
            return response.headers
        }
    }
}

public struct TydomHTTPRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data?

    public func headerValue(_ key: String) -> String? {
        headers[key.lowercased()]
    }
}

public struct TydomHTTPResponse: Sendable, Equatable {
    public let status: Int
    public let reason: String?
    public let headers: [String: String]
    public let body: Data?

    public func headerValue(_ key: String) -> String? {
        headers[key.lowercased()]
    }
}

struct TydomHTTPParser: Sendable {
    enum ParseError: Error, Sendable, Equatable {
        case missingHeaderSeparator
        case invalidStartLine
        case invalidStatusCode
    }

    init() {}

    func parse(_ data: Data) -> Result<TydomHTTPFrame, ParseError> {
        let headerSeparator = Data([13, 10, 13, 10])
        guard let separatorRange = data.range(of: headerSeparator) else {
            return .failure(.missingHeaderSeparator)
        }

        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyData = data.subdata(in: separatorRange.upperBound..<data.count)
        let headerString = String(data: headerData, encoding: .isoLatin1) ?? String(decoding: headerData, as: UTF8.self)
        let headerLines = headerString.components(separatedBy: "\r\n")
        guard let startLine = headerLines.first, startLine.isEmpty == false else {
            return .failure(.invalidStartLine)
        }

        let headers = parseHeaders(from: headerLines.dropFirst())
        let body = sliceBody(bodyData, contentLength: headers["content-length"].flatMap(Int.init))

        if startLine.hasPrefix("HTTP/") {
            let components = startLine.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 2, let status = Int(components[1]) else {
                return .failure(.invalidStatusCode)
            }
            let reason = components.count >= 3 ? components[2...].joined(separator: " ") : nil
            return .success(.response(TydomHTTPResponse(status: status, reason: reason, headers: headers, body: body)))
        }

        let components = startLine.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return .failure(.invalidStartLine)
        }
        let method = String(components[0])
        let path = String(components[1])
        return .success(.request(TydomHTTPRequest(method: method, path: path, headers: headers, body: body)))
    }

    private func parseHeaders(from lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else { continue }
            headers[key] = value
        }
        return headers
    }

    private func sliceBody(_ bodyData: Data, contentLength: Int?) -> Data? {
        guard bodyData.isEmpty == false else { return nil }
        if let contentLength, contentLength >= 0, bodyData.count >= contentLength {
            return bodyData.subdata(in: 0..<contentLength)
        }
        return bodyData
    }
}
