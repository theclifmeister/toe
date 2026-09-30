import Foundation

/// One GET that will not take in more than it was told to, from anywhere but the hosts it names.
///
/// Both of toe's network readers — the catalogue and the theme downloader — cap what they will
/// accept, and both used to apply the cap with `data.count <= limit` in a completion handler.
/// That refuses a body that is already in memory: `dataTask(with:completionHandler:)` buffers the
/// whole response before the handler runs, so the number was consulted only once the transfer had
/// finished on its own terms. The comments on those two limits promised that "something enormous
/// cannot be read into memory", and the code did not give it (#130).
///
/// This is the one place that promise is kept, so that it is kept the same way twice. It is a
/// delegate rather than a completion handler because the delegate is what sees the response
/// before the body: `didReceive response` refuses on `expectedContentLength` before a byte of
/// body has arrived, and `didReceive data` cancels the moment the bytes taken in pass the limit,
/// so what is ever in memory is the limit plus one chunk. The host and status checks live in the
/// same callback for the same reason — there is no point buffering the body of a 404, or of a
/// redirect that left GitHub, to refuse it at the end.
///
/// The hosts and the headers are the caller's: GitHub's by default, for the theme catalogue and
/// downloader it was written for; `api.anthropic.com` and a bearer token for the agents widget,
/// which is also why a refusal carries its status and `retry-after` — a 401 is a sign-in that has
/// lapsed and a 429 a server asking for quiet, and neither is the same as no answer.
///
/// The delegate is the task's own (`URLSessionTask.delegate`) rather than a session's, which is
/// what lets it ride on `URLSession.shared` — one connection pool for the six pictures of a theme —
/// instead of a session per request that would have to be invalidated to let go of it. A task
/// created *with* a completion handler bypasses the response and data callbacks entirely, which
/// is why the task here has none and the result is handed over from `didCompleteWithError`.
///
/// Every callback for one task arrives serially on the session's delegate queue, so `body` and
/// `refusal` need no lock; the only thing that touches the task from elsewhere is `cancel()`,
/// which is safe from any thread and turns into a `didCompleteWithError` here.
final class BoundedGET: NSObject, URLSessionDataDelegate {

    struct Failure: Error, CustomStringConvertible {
        let description: String
        /// The HTTP status of an answer that was refused for it; nil when there was no answer.
        var status: Int? = nil
        /// `retry-after`, in seconds, when a refused answer carried one.
        var retryAfter: TimeInterval? = nil
    }

    /// A task for `request` that completes with at most `limit` bytes, on the session's delegate
    /// queue. Not yet resumed, so the caller can keep the task to poll or cancel it.
    ///
    /// The `User-Agent` is set here because it is what every request toe makes has in common:
    /// GitHub refuses an unidentified client on some paths and rate-limits by IP; saying who
    /// this is costs nothing and makes the request explicable at the far end.
    static func task(_ request: URLRequest, limit: Int, allowedHosts: Set<String> = Upstream.allowedHosts,
                     headers: [String: String] = [:],
                     completion: @escaping (Result<Data, Failure>) -> Void) -> URLSessionTask {
        var request = request
        request.setValue("toe (macOS window manager)", forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let task = URLSession.shared.dataTask(with: request)
        // The task retains its delegate until it completes, so nothing else has to.
        task.delegate = BoundedGET(limit: limit, allowedHosts: allowedHosts, completion: completion)
        return task
    }

    private let limit: Int
    private let allowedHosts: Set<String>
    private let completion: (Result<Data, Failure>) -> Void
    private var body = Data()
    /// Why *this* delegate cancelled the task, when it did. `didCompleteWithError` cannot tell a
    /// cancellation it asked for from one the caller made — both arrive as `NSURLErrorCancelled`
    /// — so the reason is written down before the cancel is asked for.
    private var refusal: Failure?

    private init(limit: Int, allowedHosts: Set<String>, completion: @escaping (Result<Data, Failure>) -> Void) {
        self.limit = limit
        self.allowedHosts = allowedHosts
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            return refuse("no answer", completionHandler)
        }
        // After redirects, not before: what matters is where the bytes came from. The response
        // seen here is the final one — a redirect that is followed never reaches this callback —
        // so its URL is where the body is about to come from.
        guard let host = response.url?.host, allowedHosts.contains(host) else {
            return refuse("redirected off \(allowedHosts.sorted().first ?? "its host")", completionHandler)
        }
        guard http.statusCode == 200 else {
            // `retry-after` is seconds on every server toe talks to; the HTTP-date form is not
            // worth a parser, and reads as absent.
            let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            return refuse(Failure(description: "HTTP \(http.statusCode)", status: http.statusCode, retryAfter: retry),
                          completionHandler)
        }
        // A `Content-Length` past the limit is refused before any of it arrives. Absent, it is
        // `-1`, and the check below on what actually turns up is the one that binds.
        guard response.expectedContentLength <= Int64(limit) else {
            return refuse("the answer was too large", completionHandler)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Chunks already in flight can still land between the cancel and the completion.
        guard refusal == nil else { return }
        body.append(data)
        guard body.count <= limit else {
            refusal = Failure(description: "the answer was too large")
            body = Data()
            return dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Once, and last: Foundation calls this exactly one time per task, after the final data
        // callback, whether the task finished, failed, or was cancelled from either side.
        if let refusal {
            completion(.failure(refusal))
        } else if let error {
            // A cancellation with no refusal recorded is the caller's — the theme downloader's
            // deadline. Reported as what it is rather than as Foundation's "cancelled", which
            // would read as though the user had done it.
            let cancelled = (error as? URLError)?.code == .cancelled
            completion(.failure(Failure(description: cancelled ? "no answer" : error.localizedDescription)))
        } else {
            completion(.success(body))
        }
    }

    private func refuse(_ why: String, _ completionHandler: (URLSession.ResponseDisposition) -> Void) {
        refuse(Failure(description: why), completionHandler)
    }

    private func refuse(_ failure: Failure, _ completionHandler: (URLSession.ResponseDisposition) -> Void) {
        refusal = failure
        completionHandler(.cancel)
    }
}
