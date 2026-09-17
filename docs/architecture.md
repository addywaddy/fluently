# MVP decisions

- Keep Phoenix/PostgreSQL: an existing working foundation, one service, no stack migration.
- Public signup creates an account-owned workspace. Operator-issued pilot owner keys remain supported alongside account sessions. Customer reviewers still use project-specific invitations.
- Projects own reviewers and threads; all lookups are project scoped. The snippet contains only a public UUID. An exact allowed origin is additional browser protection, never authentication.
- Review links carry a separate 14-day secret in the URL fragment. The SDK removes it immediately and exchanges it plus a display name for a signed 24-hour review session. Rotating credentials revokes existing sessions. Guests can create, read, reply, and resolve; only owners can delete. Display names are self-asserted, not verified identities.
- A separate project API key grants read-only structured access for external tools. Never embed it in customer HTML.
- Anchor envelope: version, platform, type, target identity, relative point, and viewport context. Prefer explicit feedback IDs; uncertain or hidden targets remain in the thread list rather than receiving speculative pins.
- No screenshots in V1. No DOM dumps, input values, cookies, query strings or URL fragments. Exclusion applies to ancestors and target descendants; bounded selected-target text is captured only when stable IDs are absent, and can be disabled. URL paths and user-written comments may still contain personal data. Customers must mark sensitive regions and reviewers should avoid entering secrets.
- Shadow DOM isolates widget styling, not security: trusted host-page scripts can access the review session. Use only on websites the project owner trusts. No cross-origin iframe or closed shadow-root targeting in V1.
- Poll for changes and navigation at modest intervals; use layout observers for pins. Avoid patching host routing/history APIs.
- Single app instance with bounded in-memory rate limiting for the pilot. Multiple replicas need a shared limiter before scale-out.
- Deferred: screenshots/redaction pipeline, MCP, billing, automatic code changes, analytics, teams/SSO, configurable retention, native SDKs. Project deletion is available now.

## Personal landing demo and account upgrade

The configured dogfood project supplies only the landing origin. Each anonymous visitor
gets a distinct workspace, project and reviewer on their first successful comment, in
one transaction. Failed comments and page views create no account records. Reusing the
existing project boundary keeps public demo isolation independent of reviewer filters;
no shared project ever becomes publicly writable. `/demo` is a same-origin, cookie/CSRF
API, separate from the cross-origin bearer-token customer API. Both apply rate limits.

Signup upgrades the account row and reviewer in place and clears its expiry. It does not
copy comments or transfer a caller-supplied project. A locked account row serializes
signup with demo creation and retention. Session secrets are random, hashed in the DB,
and carried inside the signed HttpOnly, SameSite browser cookie (Secure in production).
Signup rotates the secret; old anonymous cookies cannot access the registered workspace.
Signout revokes the session. The pilot deliberately supports one active session per
account; a new login revokes the previous session. Accounts are independent of project
reviewers so later multi-project identities can coexist with invited guests.

Unclaimed identities expire after 14 days from creation. An hourly worker purges up to
500 expired workspaces, their threads/messages and reviewers. Claimed accounts are exempt.
Cookie loss cannot recover an anonymous identity. Logging into an existing account does
not implicitly merge another anonymous identity.

Passwords use salted PBKDF2-HMAC-SHA256 with 600,000 iterations through OTP crypto,
following the [OWASP PBKDF2 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
This avoids adding a native password dependency to the existing release. Minimum length
is 15 characters; login and signup are rate-limited. Email is an unverified login identifier,
never a basis for trusting or merging identities. Email verification and password recovery
remain a follow-up before a wider public launch; no email infrastructure is required to
exercise the demo-to-account flow locally.
