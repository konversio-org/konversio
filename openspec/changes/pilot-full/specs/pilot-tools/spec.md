## ADDED Requirements

### Requirement: Tool definition schema

A `Captain::CustomTool` SHALL be defined by `slug` (URL-safe identifier, unique per account), `title`, `description`, `endpoint_url`, `http_method` (`GET` or `POST`), `request_template` (optional templated request body for POST), `response_template` (optional templated extraction expression for the response body), `auth_type` (`none` | `bearer` | `basic` | `api_key`), `auth_config` (encrypted JSONB with method-specific fields), `param_schema` (array of objects each with `name`, `type`, `description`, `required`), `enabled` flag, and a `timeout_seconds` value capped at 30 (default 10). Tools are **account-scoped**, not assistant-scoped: a tool defined for an account is available to any assistant in that account whose configuration enables it.

#### Scenario: Admin creates a tool
- **WHEN** an admin POSTs a valid tool definition to `/api/v2/accounts/:account_id/pilot/custom_tools`
- **THEN** a `Captain::CustomTool` row is created at the account scope
- **AND** the response status is `201`
- **AND** `slug` is auto-generated from `title` if not provided, with collision handling appending a numeric suffix

#### Scenario: Invalid param schema rejected
- **WHEN** the admin POSTs a tool whose `param_schema` is not a valid JSON array of parameter objects (missing `name`, `type`, or invalid type value)
- **THEN** the response status is `422`
- **AND** the error body identifies the invalid parameter index and field

#### Scenario: Timeout cap enforced
- **WHEN** the admin POSTs a tool with `timeout_seconds: 120`
- **THEN** the persisted row has `timeout_seconds = 30` (clamped to the documented maximum)

#### Scenario: Per-account cap enforced
- **WHEN** an account already has 15 custom tools AND an admin POSTs a 16th tool
- **THEN** the response status is `422`
- **AND** the error message identifies the per-account cap

### Requirement: Outbound URL allowlist per assistant

Each `Captain::Assistant` SHALL maintain a hostname allowlist. Tool HTTP calls MUST only proceed to hosts on the allowlist of the invoking assistant. Calls to private RFC1918 ranges, link-local, loopback, and metadata endpoints (169.254.169.254) MUST be denied unconditionally, irrespective of allowlist contents (defense against DNS rebinding and SSRF via allowlisted hostnames that resolve to private addresses).

#### Scenario: Allowlisted host succeeds
- **WHEN** an assistant has allowlist `["api.example.com"]` AND a tool endpoint is `https://api.example.com/orders/{id}`
- **THEN** the tool call proceeds

#### Scenario: Non-allowlisted host rejected
- **WHEN** the same assistant has a tool endpoint `https://evil.example.org/...`
- **THEN** the tool call is rejected with error code `tool.host_not_allowed`
- **AND** the LLM receives the structured error as the tool result

#### Scenario: Private IP rejected even if allowlisted
- **WHEN** the assistant's allowlist contains `"internal.local"` which resolves to `10.0.0.5`
- **THEN** the tool call is rejected with error code `tool.private_ip_denied`

### Requirement: Synchronous tool execution within the inference loop

When an Autopilot assistant invokes a custom tool during inference, the tool HTTP call SHALL execute **synchronously inside the same request/job as the LLM call**, not as a separate Sidekiq job. The result MUST be passed back to the next LLM turn as a `tool`-role message. This matches Captain's `Captain::Tools::CustomHttpTool` behavior: the agent loop pauses, the HTTP call runs in-process, and the loop resumes with the result. Asynchronous tool execution is explicitly NOT in scope for v1.

#### Scenario: Tool selected, executed inline, result returned to LLM
- **WHEN** the LLM emits a tool call for `lookup_order` during an Autopilot inference
- **THEN** the assistant performs the HTTP request inside the same job/request
- **AND** the response body (post-template extraction) is passed to the next LLM call as a `tool`-role message
- **AND** the LLM produces the final user-facing reply incorporating the tool result

#### Scenario: Inference job ownership
- **WHEN** a tool call occurs inside `Pilot::AutopilotInferenceJob`
- **THEN** no separate `Pilot::ToolExecutionJob` is enqueued
- **AND** the entire LLM-tool-LLM round trip completes within the originating job's lifetime

### Requirement: Tool result truncation

Tool response bodies (after any `response_template` extraction) SHALL be truncated to a maximum of 8 KB of UTF-8 text before being passed back to the LLM. Larger responses MUST be truncated with a trailing `[...truncated]` marker.

#### Scenario: Small response passes through
- **WHEN** the response body is 2 KB
- **THEN** the LLM receives the full body unmodified

#### Scenario: Large response truncated
- **WHEN** the response body is 20 KB
- **THEN** the LLM receives the first 8 KB with `[...truncated]` appended

### Requirement: Structured error format for tool failures

When tool execution fails (timeout, SSRF rejection, HTTP error, parse error), the LLM SHALL receive a JSON object of the shape `{ "error": "<code>", "message": "<human-readable>" }` rather than a raw exception string. Error codes are drawn from a fixed enumeration: `tool.timeout`, `tool.host_not_allowed`, `tool.private_ip_denied`, `tool.http_error`, `tool.parse_error`, `tool.disabled`. This allows the LLM to decide whether to retry, fall back, or hand off to a human.

#### Scenario: HTTP 5xx returned as structured error
- **WHEN** a tool endpoint returns HTTP 500
- **THEN** the LLM receives `{ "error": "tool.http_error", "message": "500 Internal Server Error" }`

#### Scenario: Timeout returned as structured error
- **WHEN** the HTTP call exceeds the configured timeout
- **THEN** the LLM receives `{ "error": "tool.timeout", "message": "Tool exceeded 10s timeout" }` (or the configured value)

#### Scenario: SSRF rejection returned as structured error
- **WHEN** the host resolves to a private IP
- **THEN** the LLM receives `{ "error": "tool.private_ip_denied", "message": "Resolved address is in a denied range" }`

### Requirement: Per-assistant tool enablement

The LLM SHALL only have access to tools whose `enabled` flag is `true` AND that are enabled for the active assistant. Admins MUST be able to toggle a tool on/off at the account level (the `enabled` column) without deleting it, and SHOULD be able to filter the account-wide tool set per assistant.

#### Scenario: Account-disabled tool not offered to LLM
- **WHEN** a tool has `enabled = false` at the account level
- **THEN** the tool does not appear in any assistant's tool list
- **AND** if the LLM somehow emits a call for it, the result is `{ "error": "tool.disabled", "message": "Tool is not enabled" }`

#### Scenario: Admin toggles a tool
- **WHEN** an admin PATCHes `{"enabled": false}` on a tool
- **THEN** the tool is immediately excluded from subsequent inferences

### Requirement: Tool execution instrumentation

Tool calls SHALL be instrumented for observability with span name `pilot.tool.custom_http`, including input parameters (truncated/redacted), response HTTP status, duration in milliseconds, and any error code emitted. Instrumentation MUST work with the host application's existing observability backend (Langfuse, OpenTelemetry, or plain Rails logs) without requiring a specific provider.

#### Scenario: Successful call instrumented
- **WHEN** a tool executes successfully
- **THEN** an instrumentation span is emitted with `name = "pilot.tool.custom_http"`, `tool_slug`, `assistant_id`, `duration_ms`, `http_status`
- **AND** input params are recorded with sensitive fields redacted (auth headers, secrets matched by name pattern)

#### Scenario: Failed call instrumented
- **WHEN** a tool fails with a `tool.timeout` error
- **THEN** the instrumentation span records `error_code = "tool.timeout"` and `duration_ms`

### Requirement: Tool definition UI

The Autopilot account settings SHALL include a "Custom Tools" panel visible when `account.pilot_tools_enabled = true`. The panel MUST allow CRUD on tools (with param schema editor, endpoint configuration, hostname allowlist on assistants, auth type picker, enable toggle) and MUST support a "test tool" affordance that synchronously sends a sample argument payload and shows the live response.

#### Scenario: Panel visible with flag
- **WHEN** an admin opens an account with `pilot_tools_enabled = true`
- **THEN** a "Custom Tools" link appears in the settings navigation

#### Scenario: Test tool button
- **WHEN** an admin clicks "Test" on a tool with sample arguments
- **THEN** the tool's HTTP request is executed in-process (out-of-band of any LLM session, but using the same `ToolExecutor` code path)
- **AND** the response body (or structured error) is displayed in the panel

#### Scenario: Panel hidden without flag
- **WHEN** `pilot_tools_enabled = false`
- **THEN** the Tools panel link is not rendered AND the route returns `404`
