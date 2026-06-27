# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.0.2] - 2026-06-26

Pilot custom tools are now functional end to end. In 0.0.1 they could be
configured in the UI but never actually worked against a real
(authenticated, HTTPS) endpoint. This release fixes that and the
surrounding workflow, verified live against a production endpoint.

### Added

- Custom tools authenticate to their endpoint: Bearer token, Basic auth, or API key (header or query placement).
- Custom tool endpoint URLs support Liquid templating, e.g. `/nationality-check/{{ nationality }}`.
- `PILOT_TOOL_ALLOWED_HOSTS` — an explicit, per-host allowlist to let a custom tool reach a named internal or local endpoint past the SSRF guard.
- The Autopilot Playground shows which tools each answer used, and renders assistant replies as markdown.

### Fixed

- Custom tools now send their configured auth header — previously every authenticated endpoint returned 401.
- HTTPS custom tools behind a CDN / SNI virtual host (e.g. Cloudflare) now complete the TLS handshake (SNI uses the hostname, not the SSRF-resolved IP).
- The custom-tool enable/disable toggle persists instead of silently reverting on reload.
- Pilot reliably calls the relevant custom tool on every turn, including follow-up questions, instead of skipping it and answering from memory.
- The custom-tools dialog no longer blanks on a missing icon, and placeholder braces in examples render correctly.
- Playground send-button alignment.

### Changed

- Pilot autopilot temperature lowered to 0.3 for steadier tool use.
- Updated `markdown-it` 14.1.1 → 14.2.0 (the renderer behind assistant-message markdown).

### Security

- Updated `dompurify` 3.4.0 → 3.4.11, the HTML sanitizer that all rendered message content passes through.

## [0.0.1]

Initial Konversio release: a hard fork of Chatwoot v4.13.0 with the
`enterprise/` overlay and Captain AI removed and replaced by `Pilot::`,
Konversio's own open-source AI assistant (ai-agents SDK + RubyLLM).
100% MIT, self-hosted.
