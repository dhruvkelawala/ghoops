import Foundation

enum MacTransport {
    private static let responseLimit = 8 * 1024 * 1024
    private static let redirects = SameOriginRedirects()

    static func response(for request: URLRequest, in session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            guard let http = response as? HTTPURLResponse else {
                bytes.task.cancel()
                throw URLError(.badServerResponse)
            }
            var body = Data()
            for try await byte in bytes {
                guard body.count < responseLimit else {
                    bytes.task.cancel()
                    throw ClientError.incompatibleVersion
                }
                body.append(byte)
            }
            return (body, http)
        } catch {
            throw ClientError.transportError(error) ?? error
        }
    }
}

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let current = Origin(response.url), let next = Origin(request.url), current == next else { return nil }
        return request
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ url: URL?) {
            guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            self.scheme = scheme
            self.host = host
            self.port = url.port ?? (scheme == "https" ? 443 : 80)
        }
    }
}
