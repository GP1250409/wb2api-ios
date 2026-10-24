import Foundation
import WebKit

/// API requests must never carry the panel key to an identity-provider host.
final class PanelRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Panel endpoints are canonical; return redirects to the caller for classification.
        completionHandler(nil)
    }
}

extension URLSession {
    static let panel: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: PanelRedirectGuard(), delegateQueue: nil)
    }()
}

/// HttpOnly cookies stay in this app's persistent WK store. Never print or sync them.
enum AccessCookieBridge {
    static func eligible(_ cookie: HTTPCookie, for url: URL, now: Date = Date()) -> Bool {
        guard ["CF_Authorization", "cf_clearance"].contains(cookie.name),
              let host = url.host?.lowercased(), url.scheme?.lowercased() == "https" else { return false }
        let domain = cookie.domain.lowercased()
        let matches = domain.hasPrefix(".")
            ? host == String(domain.dropFirst()) || host.hasSuffix(domain)
            : host == domain
        guard matches else { return false }
        if let expires = cookie.expiresDate, expires <= now { return false }
        let path = url.path.isEmpty ? "/" : url.path
        return path == cookie.path || (path.hasPrefix(cookie.path) &&
            (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).first == "/"))
    }

    @MainActor
    static func header(for url: URL) async -> String? {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let matching = cookies.filter { eligible($0, for: url) }
        guard !matching.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: matching)["Cookie"]
    }

    @MainActor
    static func clear(for url: URL) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where eligible(cookie, for: url, now: .distantPast) {
            await withCheckedContinuation { continuation in
                store.delete(cookie) { continuation.resume() }
            }
        }
    }
}
