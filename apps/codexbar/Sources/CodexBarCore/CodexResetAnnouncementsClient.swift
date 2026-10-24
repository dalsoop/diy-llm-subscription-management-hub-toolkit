import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol CodexResetAnnouncementsFetching: Sendable {
    func fetch(from url: URL) async throws -> CodexResetAnnouncements
}

/// An isolated session: no browser cookies, account credentials, or persistent HTTP cache.
public struct CodexResetAnnouncementsClient: CodexResetAnnouncementsFetching {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        self.session = URLSession(
            configuration: config,
            delegate: HTTPSRedirectDelegate(),
            delegateQueue: nil)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func fetch(from url: URL) async throws -> CodexResetAnnouncements {
        guard CodexResetAnnouncements.providerURL(url.absoluteString) != nil else {
            throw CodexResetAnnouncementsError.invalidURL
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15)
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept")
        request.setValue(
            "CodexBar-ResetAnnouncements/1.0",
            forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let (data, response) = try await self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CodexResetAnnouncementsError.unavailable }
        if response.statusCode == 429 || response.statusCode == 503 {
            throw CodexResetAnnouncementsError.retryLater(Self.retryDelay(response))
        }
        guard response.statusCode == 200 else { throw CodexResetAnnouncementsError.unavailable }
        guard data.count <= 2_000_000 else { throw CodexResetAnnouncementsError.unsupportedResponse }
        do {
            return try CodexResetAnnouncements.decode(data)
        } catch {
            throw CodexResetAnnouncementsError.unsupportedResponse
        }
    }

    private static func retryDelay(_ response: HTTPURLResponse) -> TimeInterval {
        let header = response.value(forHTTPHeaderField: "Retry-After") ?? ""
        if let seconds = TimeInterval(header), seconds.isFinite {
            return max(60, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return max(60, formatter.date(from: header)?.timeIntervalSinceNow ?? 300)
    }
}

private final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void)
    {
        guard let url = request.url, CodexResetAnnouncements.providerURL(url.absoluteString) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
