## Capability: pilot-citation-source-url-validation

Network-level eligibility rules deciding whether a knowledge document's source link may be shown to end customers as a citation URL. This capability layers onto `pilot-response-citations` (change `pilot-agent-sessions-and-citations`), which owns how cited indexes map to documents and how URLs are rendered; here only the per-document eligibility check is specified. The check runs at citation-resolution time, not only at document save time, because DNS answers and document state change.

---

## ADDED Requirements

### Requirement: customer-visible source URLs pass network-level validation

A knowledge document SHALL yield a customer-visible source URL only when all of the following hold: the document is web-backed (not an uploaded file); the link parses as an `http` or `https` URI with a present host and no embedded credentials; the host resolves via DNS; and every resolved IP address is publicly routable. Any failure — malformed link, unresolvable host, DNS error, or any resolved address in a private, loopback, link-local, or otherwise non-public range for IPv4 or IPv6 (including translation prefixes that map back to local address space) — MUST make the document yield no URL. Links whose path ends in `.pdf` MUST also yield no URL, matching the exclusion of uploaded PDFs.

#### Scenario: ordinary public URL is eligible

- Given a web-backed document whose https link resolves only to public IP addresses
- When the customer-visible source URL is evaluated
- Then the link is returned as-is

#### Scenario: private, loopback, and link-local targets are ineligible

- Given a web-backed document whose host resolves to a private, loopback, link-local, or reserved address (IPv4 or IPv6)
- When the customer-visible source URL is evaluated
- Then no URL is yielded

#### Scenario: mixed resolution is ineligible

- Given a web-backed document whose host resolves to both a public and a non-public address
- When the customer-visible source URL is evaluated
- Then no URL is yielded

#### Scenario: unresolvable or failing DNS is ineligible

- Given a web-backed document whose host returns no addresses or whose resolution errors
- When the customer-visible source URL is evaluated
- Then no URL is yielded

#### Scenario: malformed links and embedded credentials are ineligible

- Given a web-backed document whose link is not a valid http(s) URI, has no host, or contains userinfo
- When the customer-visible source URL is evaluated
- Then no URL is yielded

#### Scenario: file-backed documents and PDF links are ineligible

- Given a document backed by an uploaded PDF or markdown file, or a web-backed document whose link path ends in `.pdf`
- When the customer-visible source URL is evaluated
- Then no URL is yielded

---

### Requirement: citation resolution applies the eligibility check per cited document

When a Pilot reply assembles customer-visible citations, the system SHALL evaluate this eligibility check for each cited document and SHALL omit any citation index whose document yields no URL, without failing the reply.

#### Scenario: ineligible cited document is silently omitted

- Given a Pilot reply citing two documents, one eligible and one whose host resolves to a private address
- When trusted citation URLs are resolved
- Then only the eligible document's index maps to a URL
- And the reply is still delivered with the remaining citation

#### Scenario: eligibility reflects current DNS state

- Given a document whose host resolved publicly at ingestion time but now resolves to a non-public address
- When citation URLs are resolved for a new reply
- Then the document yields no URL
