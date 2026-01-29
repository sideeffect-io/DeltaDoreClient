import Foundation

#if canImport(Network)
import Network

public extension TydomGatewayDiscovery.Dependencies {
    static func live() -> TydomGatewayDiscovery.Dependencies {
        TydomGatewayDiscovery.Dependencies(
            discoverBonjour: { serviceTypes, timeout in
                guard serviceTypes.isEmpty == false else { return [] }
                return await BonjourDiscovery.discover(serviceTypes: serviceTypes, timeout: timeout)
            },
            subnetHosts: {
                NetworkProbe.subnetHosts()
            },
            probeHost: { host, port, timeout in
                await NetworkProbe.tcpProbe(host: host, port: port, timeout: timeout)
            }
        )
    }
}

private enum BonjourDiscovery {
    static func discover(serviceTypes: [String], timeout: TimeInterval) async -> [String] {
        await withTaskGroup(of: [String].self) { group in
            for serviceType in serviceTypes {
                group.addTask {
                    await browse(serviceType: serviceType, timeout: timeout)
                }
            }
            var hosts: [String] = []
            for await result in group {
                hosts.append(contentsOf: result)
            }
            return Array(Set(hosts))
        }
    }

    private static func browse(serviceType: String, timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .init())
            let hosts = LockedHosts()
            let gate = ContinuationGate()
            let queue = DispatchQueue(label: "tydom.bonjour.browser")

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    switch result.endpoint {
                    case .hostPort(let host, _):
                        hosts.append(host.debugDescription)
                    default:
                        continue
                    }
                }
            }

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    browser.cancel()
                    gate.resumeOnce(continuation, value: [])
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                browser.cancel()
                gate.resumeOnce(continuation, value: hosts.snapshot())
            }
        }
    }
}

private enum NetworkProbe {
    static func tcpProbe(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            guard port > 0, port <= 65535, let portValue = UInt16(exactly: port) else {
                continuation.resume(returning: false)
                return
            }
            let endpoint = NWEndpoint.Host(host)
            let parameters = NWParameters.tcp
            let gate = ContinuationGate()
            guard let nwPort = NWEndpoint.Port(rawValue: portValue) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: endpoint, port: nwPort, using: parameters)
            let queue = DispatchQueue(label: "tydom.tcp.probe")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    gate.resumeOnce(continuation, value: true)
                case .failed:
                    connection.cancel()
                    gate.resumeOnce(continuation, value: false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                gate.resumeOnce(continuation, value: false)
            }
        }
    }

    static func subnetHosts() -> [String] {
        var addresses: [String] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer = ifaddrPointer
        while pointer != nil {
            guard let ifaddr = pointer?.pointee else { break }
            let flags = Int32(ifaddr.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp && isRunning && !isLoopback else {
                pointer = ifaddr.ifa_next
                continue
            }

            guard let addrPointer = ifaddr.ifa_addr, let maskPointer = ifaddr.ifa_netmask else {
                pointer = ifaddr.ifa_next
                continue
            }

            let addrFamily = addrPointer.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let addr = addrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                let ip = UInt32(bigEndian: addr.sin_addr.s_addr)
                let netmask = UInt32(bigEndian: mask.sin_addr.s_addr)
                let network = ip & netmask
                let broadcast = network | ~netmask

                if broadcast >= network + 2 {
                    for host in (network + 1)..<broadcast {
                        if host == ip { continue }
                        addresses.append(ipv4String(host))
                    }
                }
            }

            pointer = ifaddr.ifa_next
        }
        return addresses
    }

    private static func ipv4String(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce<T: Sendable>(_ continuation: CheckedContinuation<T, Never>, value: T) {
        lock.lock()
        let shouldResume = !didResume
        if shouldResume {
            didResume = true
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

private final class LockedHosts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ host: String) {
        lock.lock()
        values.append(host)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        let snapshot = Array(Set(values))
        lock.unlock()
        return snapshot
    }
}
#endif
