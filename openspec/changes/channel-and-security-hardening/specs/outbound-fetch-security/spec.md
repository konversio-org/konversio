## Capability: outbound-fetch-security

SSRF-safe outbound HTTP fetching for all server-initiated requests to operator- or contact-supplied URLs (webhook delivery, attachment imports, avatar fetches), with size, timeout, content-type, redirect, and header-safety controls, plus an explicit opt-in for private-network targets.

---

## ADDED Requirements

### Requirement: SafeFetch provides a single hardened fetch entry point

The system SHALL provide a `SafeFetch.fetch(url, **options)` entry point that validates the URL scheme (http/https only), resolves and pins the target IP through `ssrf_filter`, streams the response body to a tempfile, and yields a result exposing `tempfile`, `filename`, and `content_type`. A block MUST be required.

#### Scenario: non-HTTP scheme is rejected

- Given a caller fetches `ftp://example.com/file`
- When `SafeFetch.fetch` is called
- Then a `SafeFetch::InvalidUrlError` is raised

#### Scenario: private or loopback target is rejected by default

- Given `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` is not set
- When a caller fetches `http://169.254.169.254/latest/meta-data`
- Then a `SafeFetch::UnsafeUrlError` is raised

#### Scenario: DNS resolution failure is an unsafe URL

- Given a URL whose hostname does not resolve
- When `SafeFetch.fetch` is called
- Then a `SafeFetch::UnsafeUrlError` is raised

#### Scenario: result exposes tempfile, filename, and content type

- Given a successful fetch of `https://example.com/assets/logo.png`
- When the response is a 200 with content type `image/png`
- Then the yielded result has a readable tempfile, filename `logo.png`, and content type `image/png`

---

### Requirement: Response size is capped while streaming

The fetcher MUST abort with `SafeFetch::FileTooLargeError` as soon as the streamed body exceeds the effective byte cap, where the cap is the explicit `max_bytes` option or, by default, the configured maximum upload size (falling back to 40 MB when unset or non-positive).

#### Scenario: oversized response is aborted mid-stream

- Given an endpoint streaming a 100 MB body
- When `SafeFetch.fetch` is called with the default cap
- Then a `SafeFetch::FileTooLargeError` is raised before the full body is written

#### Scenario: explicit max_bytes overrides the default

- Given `SafeFetch.fetch` is called with `max_bytes: 1.kilobyte`
- When the endpoint returns 2 KB
- Then a `SafeFetch::FileTooLargeError` is raised

---

### Requirement: Content types are validated against an allowlist

Unless `validate_content_type: false` is passed, the fetcher MUST reject responses whose normalized content type (lowercased, parameters stripped) matches neither the allowed prefixes (default `image/`, `video/`) nor the explicitly allowed types, raising `SafeFetch::UnsupportedContentTypeError`.

#### Scenario: disallowed content type is rejected

- Given an endpoint returning `text/html`
- When `SafeFetch.fetch` is called with default options
- Then a `SafeFetch::UnsupportedContentTypeError` is raised

#### Scenario: validation can be disabled per call

- Given an endpoint returning `application/json`
- When `SafeFetch.fetch` is called with `validate_content_type: false`
- Then the fetch succeeds

---

### Requirement: Timeouts and network failures are normalized

Open and read timeouts MUST default to 2 and 20 seconds respectively and be overridable per call. Connection, TLS, DNS socket, and timeout failures MUST be normalized to `SafeFetch::FetchError`; non-2xx responses MUST raise `SafeFetch::HttpError` carrying the status code and message.

#### Scenario: slow endpoint raises FetchError

- Given an endpoint that never responds within the read timeout
- When `SafeFetch.fetch` is called
- Then a `SafeFetch::FetchError` is raised

#### Scenario: HTTP 500 raises HttpError with the status

- Given an endpoint returning 500
- When `SafeFetch.fetch` is called
- Then a `SafeFetch::HttpError` is raised whose message starts with `500`

---

### Requirement: Requests support method, body, headers, and basic auth

The fetcher MUST support the HTTP methods supported by `ssrf_filter`, reject unsupported methods with `SafeFetch::UnsupportedMethodError`, send a request body and custom headers when supplied, and apply HTTP basic authentication from an explicit option or from userinfo in the URL — forwarding URL-embedded credentials only to same-origin redirect targets.

#### Scenario: unsupported method is rejected

- Given `SafeFetch.fetch` is called with `method: :trace`
- Then a `SafeFetch::UnsupportedMethodError` is raised

#### Scenario: credentials are not forwarded cross-origin

- Given a fetch of `https://user:pass@a.example/x` that redirects to `https://b.example/y`
- When the redirect is followed
- Then the second request carries no `Authorization` header derived from the original URL userinfo

---

### Requirement: Private-network fetching is an explicit opt-in with retained safeguards

When `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` is set to a truthy value, fetches to private/loopback addresses MUST be permitted through a dedicated private-network request path that still: validates the scheme, follows at most the default redirect budget, pins the connection to a resolved IP address, strips sensitive headers (`authorization`, `cookie`, `proxy-authorization`, plus caller-supplied extras) when a redirect crosses origins, and rejects any header name or value containing CR/LF characters.

#### Scenario: private webhook endpoint works when opted in

- Given `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`
- And a webhook target at `http://192.168.1.10:9000/hook`
- When a webhook is delivered
- Then the request succeeds

#### Scenario: sensitive headers stripped on cross-origin redirect

- Given private-network mode is enabled
- And the original request carries an `Authorization` header
- When the target redirects to a different origin
- Then the redirected request omits `Authorization`, `Cookie`, and `Proxy-Authorization`

#### Scenario: CRLF in a header value is rejected

- Given a caller passes a header value containing `\r\n`
- When the request is built
- Then the fetch fails with an unsafe-URL error before any bytes are sent

---

### Requirement: Webhook delivery uses SafeFetch

`Webhooks::Trigger` MUST deliver account, inbox, and agent-bot webhook payloads through `SafeFetch.fetch` with `method: :post` and content-type validation disabled, using the configured webhook timeout (default 5 seconds) for both open and read timeouts, and MUST NOT use `RestClient` for delivery.

#### Scenario: webhook POST goes through SafeFetch

- Given an account webhook subscribed to `message_created`
- When a message is created
- Then the payload is delivered via `SafeFetch.fetch` with a JSON body and `Content-Type: application/json`

#### Scenario: SSRF-target webhook URL fails closed

- Given an account webhook whose URL resolves to a private address
- And private-network mode is disabled
- When a subscribed event fires
- Then delivery fails with an unsafe-URL error and is logged as an invalid webhook URL

---

### Requirement: Agent-bot webhook failures map HTTP statuses for retry

For agent-bot webhooks, a `SafeFetch::HttpError` with status 429 or 500 MUST be re-raised as a retryable error carrying the status; other delivery failures MUST follow the existing failure handling (pending conversations re-open with an activity message unless the account keeps them pending; API-inbox messages are marked failed with the error).

#### Scenario: agent bot 429 is retryable

- Given an agent bot webhook endpoint returning 429
- When delivery is attempted
- Then a retryable error carrying status 429 is raised for job retry

#### Scenario: failed API-inbox delivery marks the message failed

- Given an API inbox with a webhook URL that returns 400
- When a `message_created` delivery fails
- Then the message status becomes `failed` with the error message recorded

---

### Requirement: Signed webhook requests carry Konversio-branded headers

When a webhook has a secret, deliveries MUST include a delivery identifier header when present, a unix-timestamp header, and an HMAC-SHA256 signature header of the form `sha256=<hex>` computed over `<timestamp>.<body>`, using the `X-Konversio-Delivery`, `X-Konversio-Timestamp`, and `X-Konversio-Signature` header names.

#### Scenario: signature verifiable by the receiver

- Given a webhook with secret `s` subscribed to `conversation_created`
- When a delivery is made with body `B` and timestamp `T`
- Then the receiver can recompute `sha256=` + HMAC-SHA256(`s`, `"T.B"`) and match the `X-Konversio-Signature` header
