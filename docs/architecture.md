# MVP decisions

- Keep Phoenix/PostgreSQL: an existing working foundation, one service, no stack migration.
- Invite-only pilot workspaces. Provision one owner access key per workspace with a Mix task. Keys are high-entropy bearer secrets, hashed at rest. A signed, short-lived same-site browser session protects the management UI. No public signup or email dependency. Team accounts can replace owner keys later without changing project ownership.
- Projects own reviewers and threads; all lookups are project scoped. The snippet contains only a public UUID. An exact allowed origin is additional browser protection, never authentication.
- Review links carry a separate 14-day secret in the URL fragment. The SDK removes it immediately and exchanges it plus a display name for a signed 24-hour review session. Rotating credentials revokes existing sessions. Guests can create, read, reply, and resolve; only owners can delete. Display names are self-asserted, not verified identities.
- A separate project API key grants read-only structured access for external tools. Never embed it in customer HTML.
- Anchor envelope: version, platform, type, target identity, relative point, and viewport context. Prefer explicit feedback IDs; uncertain or hidden targets remain in the thread list rather than receiving speculative pins.
- No screenshots in V1. No DOM dumps, input values, cookies, query strings or URL fragments. Exclusion applies to ancestors and target descendants; bounded selected-target text is captured only when stable IDs are absent, and can be disabled. URL paths and user-written comments may still contain personal data. Customers must mark sensitive regions and reviewers should avoid entering secrets.
- Shadow DOM isolates widget styling, not security: trusted host-page scripts can access the review session. Use only on websites the project owner trusts. No cross-origin iframe or closed shadow-root targeting in V1.
- Poll for changes and navigation at modest intervals; use layout observers for pins. Avoid patching host routing/history APIs.
- Single app instance with bounded in-memory rate limiting for the pilot. Multiple replicas need a shared limiter before scale-out.
- Deferred: screenshots/redaction pipeline, MCP, billing, automatic code changes, analytics, teams/SSO, configurable retention, native SDKs. Project deletion is available now.
