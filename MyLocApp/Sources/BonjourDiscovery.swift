import Foundation
import Network

/// Discovers the dynamic TCP port of iOS's local `_remotepairing-manual-pairing._tcp`
/// or `_remotepairing._tcp` Bonjour service so in-app pairing connects to the real port.
enum BonjourDiscovery {
    private final class OneShotGate: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let browser: NWBrowser
        private let continuation: CheckedContinuation<UInt16?, Never>

        init(browser: NWBrowser, continuation: CheckedContinuation<UInt16?, Never>) {
            self.browser = browser
            self.continuation = continuation
        }

        func finish(_ port: UInt16?) {
            lock.lock()
            if done {
                lock.unlock()
                return
            }
            done = true
            lock.unlock()
            browser.cancel()
            continuation.resume(returning: port)
        }
    }

    static func discoverRemotePairingPort(timeoutSeconds: Double = 4.0) async -> UInt16? {
        if let port = await browse(serviceType: "_remotepairing-manual-pairing._tcp", timeout: timeoutSeconds / 2) {
            return port
        }
        return await browse(serviceType: "_remotepairing._tcp", timeout: timeoutSeconds / 2)
    }

    private static func browse(serviceType: String, timeout: Double) async -> UInt16? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.myloc.bonjour.\(serviceType)")
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: .tcp)
            let gate = OneShotGate(browser: browser, continuation: continuation)

            browser.browseResultsChangedHandler = { results, _ in
                guard let first = results.first else { return }
                let conn = NWConnection(to: first.endpoint, using: .tcp)
                conn.stateUpdateHandler = { state in
                    if case .ready = state {
                        if let remote = conn.currentPath?.remoteEndpoint,
                           case .hostPort(_, let port) = remote {
                            conn.cancel()
                            gate.finish(port.rawValue)
                            return
                        }
                        conn.cancel()
                    } else if case .failed = state {
                        conn.cancel()
                    }
                }
                conn.start(queue: queue)
            }

            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                gate.finish(nil)
            }
        }
    }
}
