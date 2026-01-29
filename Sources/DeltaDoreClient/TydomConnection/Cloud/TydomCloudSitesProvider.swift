import Foundation

public struct TydomCloudSitesProvider {
    struct Constants {
        static let siteAccessListAPI = "https://prod.iotdeltadore.com/sitesmanagement/api/v1/siteaccesslist"
    }

    public struct Site: Sendable, Equatable {
        public let id: String
        public let name: String
        public let gateways: [Gateway]
    }

    public struct Gateway: Sendable, Equatable {
        public let mac: String
        public let name: String?
    }

    public enum ProviderError: Error, Sendable {
        case invalidResponse
        case missingAccessToken
        case invalidPayload(String)
    }

    public static func fetchSites(
        email: String,
        password: String,
        session: URLSession
    ) async throws -> [Site] {
        let accessToken = try await TydomCloudPasswordProvider.fetchAccessToken(
            email: email,
            password: password,
            session: session
        )
        return try await fetchSites(accessToken: accessToken, session: session)
    }

    public static func fetchSites(
        accessToken: String,
        session: URLSession
    ) async throws -> [Site] {
        let data = try await fetchSitesPayload(accessToken: accessToken, session: session)
        return try decodeSites(from: data)
    }

    public static func fetchSitesPayload(
        email: String,
        password: String,
        session: URLSession
    ) async throws -> Data {
        let accessToken = try await TydomCloudPasswordProvider.fetchAccessToken(
            email: email,
            password: password,
            session: session
        )
        return try await fetchSitesPayload(accessToken: accessToken, session: session)
    }

    public static func fetchSitesPayload(
        accessToken: String,
        session: URLSession
    ) async throws -> Data {
        guard let url = URL(string: Constants.siteAccessListAPI) else { throw ProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }
        return data
    }

    private static func decodeSites(from data: Data) throws -> [Site] {
        if let decoded = try? JSONDecoder().decode(SiteAccessListResponse.self, from: data) {
            return decoded.sites.map { site in
                Site(
                    id: site.id,
                    name: site.name,
                    gateways: site.gateways.map { gateway in
                        Gateway(mac: TydomMac.normalize(gateway.mac), name: gateway.name)
                    }
                )
            }
        }

        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let arrays = extractCandidateArrays(from: json)
        for array in arrays {
            let sites = array.compactMap(parseSite(from:))
            if sites.isEmpty == false {
                return sites
            }
        }

        let snippet = String(data: data, encoding: .utf8)?.prefix(4000) ?? "<non-utf8>"
        throw ProviderError.invalidPayload(String(snippet))
    }
}

private func extractCandidateArrays(from json: Any) -> [[[String: Any]]] {
    var results: [[[String: Any]]] = []

    if let array = json as? [[String: Any]] {
        results.append(array)
        return results
    }

    if let dict = json as? [String: Any] {
        for value in dict.values {
            results.append(contentsOf: extractCandidateArrays(from: value))
        }
        return results
    }

    if let array = json as? [Any] {
        let dicts = array.compactMap { $0 as? [String: Any] }
        if dicts.isEmpty == false {
            results.append(dicts)
        }
        for value in array {
            results.append(contentsOf: extractCandidateArrays(from: value))
        }
    }

    return results
}

private func parseSite(from dict: [String: Any]) -> TydomCloudSitesProvider.Site? {
    let sitePayload = dict["site"] as? [String: Any] ?? dict
    let id = (sitePayload["id"] as? String)
        ?? (dict["id"] as? String)
        ?? (dict["siteId"] as? String)
        ?? (dict["site_id"] as? String)
        ?? UUID().uuidString
    let name = (dict["label"] as? String)
        ?? (sitePayload["label"] as? String)
        ?? (sitePayload["name"] as? String)
        ?? (dict["name"] as? String)
        ?? (dict["siteName"] as? String)
        ?? "Unnamed Site"

    var gateways: [TydomCloudSitesProvider.Gateway] = []
    if let gatewayDict = sitePayload["gateway"] as? [String: Any] {
        if let gateway = parseGateway(from: gatewayDict) {
            gateways.append(gateway)
        }
    }
    if let gatewaysArray = sitePayload["gateways"] as? [[String: Any]] {
        gateways.append(contentsOf: gatewaysArray.compactMap(parseGateway(from:)))
    }
    if gateways.isEmpty, let gatewayDict = dict["gateway"] as? [String: Any] {
        if let gateway = parseGateway(from: gatewayDict) {
            gateways.append(gateway)
        }
    }

    guard gateways.isEmpty == false else { return nil }
    return TydomCloudSitesProvider.Site(id: id, name: name, gateways: gateways)
}

private func parseGateway(from dict: [String: Any]) -> TydomCloudSitesProvider.Gateway? {
    let mac = (dict["mac"] as? String)
        ?? (dict["gatewayMac"] as? String)
        ?? (dict["gateway_mac"] as? String)
    guard let mac else { return nil }
    let name = dict["name"] as? String
        ?? dict["label"] as? String
    return TydomCloudSitesProvider.Gateway(mac: TydomMac.normalize(mac), name: name)
}

private struct SiteAccessListResponse: Decodable {
    let sites: [SiteAccess]

    init(from decoder: Decoder) throws {
        var decodedSites: [SiteAccess]?
        let keyed = try? decoder.container(keyedBy: DynamicCodingKeys.self)
        if let keyed {
            decodedSites = decodedSites ?? (try? keyed.decode([SiteAccess].self, forKey: DynamicCodingKeys("sites")))
            decodedSites = decodedSites ?? (try? keyed.decode([SiteAccess].self, forKey: DynamicCodingKeys("siteAccessList")))
            decodedSites = decodedSites ?? (try? keyed.decode([SiteAccess].self, forKey: DynamicCodingKeys("site_access_list")))
            if decodedSites == nil,
               let dataContainer = try? keyed.nestedContainer(
                   keyedBy: DynamicCodingKeys.self,
                   forKey: DynamicCodingKeys("data")
               ) {
                decodedSites = decodedSites ?? (try? dataContainer.decode([SiteAccess].self, forKey: DynamicCodingKeys("sites")))
                decodedSites = decodedSites ?? (try? dataContainer.decode([SiteAccess].self, forKey: DynamicCodingKeys("siteAccessList")))
                decodedSites = decodedSites ?? (try? dataContainer.decode([SiteAccess].self, forKey: DynamicCodingKeys("site_access_list")))
            }
        }

        if decodedSites == nil {
            let single = try decoder.singleValueContainer()
            decodedSites = try? single.decode([SiteAccess].self)
        }

        if let decodedSites {
            self.sites = decodedSites
        } else {
            let context = DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported site access list response format."
            )
            throw DecodingError.dataCorrupted(context)
        }
    }
}

private struct DynamicCodingKeys: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private struct SiteAccess: Decodable {
    let id: String
    let name: String
    let gateways: [GatewayAccess]
}

private struct GatewayAccess: Decodable {
    let mac: String
    let name: String?
}
