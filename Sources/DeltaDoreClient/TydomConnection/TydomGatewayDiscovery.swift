import Foundation

public struct TydomLocalGateway: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case cachedIP
        case bonjour
        case subnetProbe
    }

    public let mac: String
    public let host: String
    public let method: Method
}

public struct TydomGatewayDiscoveryConfig: Sendable, Equatable {
    public let discoveryTimeout: TimeInterval
    public let probeTimeout: TimeInterval
    public let probeConcurrency: Int
    public let probePorts: [Int]
    public let bonjourServiceTypes: [String]

    public init(
        discoveryTimeout: TimeInterval = 4,
        probeTimeout: TimeInterval = 1.5,
        probeConcurrency: Int = 12,
        probePorts: [Int] = [443],
        bonjourServiceTypes: [String] = []
    ) {
        self.discoveryTimeout = discoveryTimeout
        self.probeTimeout = probeTimeout
        self.probeConcurrency = probeConcurrency
        self.probePorts = probePorts
        self.bonjourServiceTypes = bonjourServiceTypes
    }
}

public struct TydomGatewayDiscovery: Sendable {
    public struct Dependencies: Sendable {
        public let discoverBonjour: @Sendable (_ serviceTypes: [String], _ timeout: TimeInterval) async -> [String]
        public let subnetHosts: @Sendable () -> [String]
        public let probeHost: @Sendable (_ host: String, _ port: Int, _ timeout: TimeInterval) async -> Bool
    }

    public let dependencies: Dependencies

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public func discover(
        mac: String,
        cachedIP: String?,
        config: TydomGatewayDiscoveryConfig
    ) async -> [TydomLocalGateway] {
        var candidates: [TydomLocalGateway] = []

        if let cachedIP, cachedIP.isEmpty == false {
            candidates.append(
                TydomLocalGateway(mac: TydomMac.normalize(mac), host: cachedIP, method: .cachedIP)
            )
        }

        let bonjourHosts = await dependencies.discoverBonjour(
            config.bonjourServiceTypes,
            config.discoveryTimeout
        )
        candidates.append(contentsOf: bonjourHosts.map {
            TydomLocalGateway(mac: TydomMac.normalize(mac), host: $0, method: .bonjour)
        })

        let subnetHosts = dependencies.subnetHosts()
        let probeHosts = await probeHosts(
            subnetHosts,
            ports: config.probePorts,
            timeout: config.probeTimeout,
            maxConcurrent: max(config.probeConcurrency, 1)
        )
        candidates.append(contentsOf: probeHosts.map {
            TydomLocalGateway(mac: TydomMac.normalize(mac), host: $0, method: .subnetProbe)
        })

        return uniqueCandidates(candidates)
    }

    private func uniqueCandidates(_ candidates: [TydomLocalGateway]) -> [TydomLocalGateway] {
        var seen: Set<String> = []
        var result: [TydomLocalGateway] = []
        for candidate in candidates {
            let key = "\(candidate.host)-\(candidate.method.rawValue)"
            if seen.insert(key).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    private func probeHosts(
        _ hosts: [String],
        ports: [Int],
        timeout: TimeInterval,
        maxConcurrent: Int
    ) async -> [String] {
        guard hosts.isEmpty == false, ports.isEmpty == false else { return [] }

        let semaphore = AsyncSemaphore(value: maxConcurrent)
        var matches: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for host in hosts {
                for port in ports {
                    group.addTask {
                        await semaphore.acquire()
                        let ok = await dependencies.probeHost(host, port, timeout)
                        await semaphore.release()
                        return ok ? host : nil
                    }
                }
            }

            for await candidate in group {
                if let candidate {
                    matches.append(candidate)
                }
            }
        }
        return Array(Set(matches))
    }
}

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func acquire() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty == false {
            let continuation = waiters.removeFirst()
            continuation.resume()
        } else {
            value += 1
        }
    }
}
