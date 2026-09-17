# MVP decisions

- Phoenix/SQLite monolith: one application instance with persistent local storage. See the SQLite decision below.
- Public signup creates an account-owned workspace. Operator-issued pilot owner keys remain supported alongside account sessions. Customer reviewers still use project-specific invitations.
- Projects own reviewers and threads; all lookups are project scoped. The snippet contains only a public UUID. An exact allowed origin is additional browser protection, never authentication.
- Review links carry a separate 14-day secret in the URL fragment. The SDK removes it immediately and exchanges it plus a display name for a signed 24-hour review session. Rotating credentials revokes existing sessions. Guests can create, read, reply, and resolve; reviewers can delete their own replies or delete a thread they started; owners can moderate threads through the dashboard. Deleting an opening message deletes the complete thread, with an explicit UI warning. Message deletion and reply creation lock the parent thread to serialize concurrent changes. Display names are self-asserted, not verified identities.
- A separate project API key grants read-only structured access for external tools. Never embed it in customer HTML.
- Anchor envelope: version, platform, type, target identity, relative point, and viewport context. Prefer explicit feedback IDs; uncertain or hidden targets remain in the thread list rather than receiving speculative pins.
- Optional previewed element snapshots are supported (see below). No DOM dumps, input values, cookies, query strings or URL fragments. Exclusion applies to ancestors and target descendants; bounded selected-target text is captured only when stable IDs are absent, and can be disabled. URL paths and user-written comments may still contain personal data. Customers must mark sensitive regions and reviewers should avoid entering secrets.
- Shadow DOM isolates widget styling, not security: trusted host-page scripts can access the review session. Use only on websites the project owner trusts. No cross-origin iframe or closed shadow-root targeting in V1.
- Display pins at a fixed top-right inset rather than the recorded click percentage. The original point remains structured context; the visible badge identifies the whole element and does not claim to track a word through reflow. Comments resolving to the same visible DOM element share a badge.
- Poll for changes and navigation at modest intervals; use layout observers for pins. Avoid patching host routing/history APIs.
- Single app instance with bounded in-memory rate limiting for the pilot. Multiple replicas need a shared limiter before scale-out.
- Deferred: automated privacy-risk/redaction pipeline, MCP, billing, automatic code changes, analytics, teams/SSO, configurable retention, native SDKs. Project deletion is available now.

## Personal landing demo and account upgrade

The configured dogfood project supplies the canonical storage origin. The private demo
checks browser Origin against the serving request origin (including scheme and port),
retains CSRF protection, and presents comment URLs at that serving origin. This permits
local address aliases without weakening customer projects’ exact-origin boundary. Each anonymous visitor
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

## SQLite (2026-09-17)

Use `ecto_sqlite3` in every environment. The pilot has short writes and frequent reads;
removing a separate database server simplifies development and single-host deployment.
WAL permits concurrent reads, foreign keys remain enforced, synchronous FULL protects
committed local writes, and a 5-second busy timeout handles brief writer contention.
All Ecto transactions default to IMMEDIATE: reserve the writer before reading, so
signup/expiry and reply/deletion decisions remain atomic without PostgreSQL row locks.
Password hashing stays outside transactions. Database sandbox tests run synchronously.

The two initial migrations were adapted for fresh SQLite installations (including the
status check constraint). This is a deliberate pre-production backend replacement,
not a migration to run against a deployed PostgreSQL database. Existing local data was
exported and imported with IDs, timestamps, binary credential hashes and JSON preserved;
the old PostgreSQL database remains untouched for rollback.

Deploy one application instance on persistent local storage. SQLite is not a shared-disk
clustering solution. Litestream runs as a separate Kamal accessory sharing that volume; backup configuration
is included, but remote replication and restoration must be verified when deployed.

## Kamal deployment (2026-09-17)

Use Kamal 2 to deploy the existing Docker image containing a Mix release. This keeps
Elixir's standard runtime packaging and provides SSH-based deployment, registry builds,
HTTPS and health-gated routing without maintaining our own systemd deployment scripts.
Ruby/Kamal run on the operator's machine, not in the application image.

One configured server mounts the named `fluently_data` volume. New containers run
migrations before starting Phoenix, then `/up` checks database connectivity before
Kamal routes traffic. Rolling deployments briefly overlap two releases on the same
host/volume; SQLite serializes writes, but both releases must understand the schema.
Only backward-compatible migrations belong in normal rolling deploys. Destructive
changes require maintenance downtime and a tested backup. Rate limiting remains
per-process during this brief overlap. Rollback changes the image, not database state.


Litestream is pinned to 0.5.14 and runs independently of Phoenix deployments. Both
containers use UID/GID 65534 to avoid SQLite WAL/SHM ownership conflicts. Prepare the
named volume before the first accessory boot: Kamal starts accessories before the app,
so relying on the app image to initialize volume permissions is insufficient. A dedicated
Hetzner Nuremberg bucket holds daily snapshots with seven-day retention. Replication is
asynchronous, not failover; backup freshness and a restore drill are deployment checks.

## Element snapshots (2026-09-17)

The SDK captures only after an explicit request and shows a removable preview. Posting
creates the comment first, then attaches the preview in a separate bounded request.
This makes capture/upload failure independent of the conversation and supports retries
without duplicate comments. It records a historical rendering; anchors remain the source
of live pin placement. The vendored MIT html-to-image library adds about 16 KiB to the
minified embed and avoids new build tooling or runtime CDN dependencies.

A dedicated SQLite attachment table keeps one immutable PNG per thread. This deliberately
defers object storage: bounded pilot images can share existing transactional deletion,
retention and Litestream backup. Metadata is preloaded without image bytes; images are
retrieved separately through the same project boundary and no-store JSON responses.
Uploads require the thread's author, use existing rate limits, allow only bounded raster
PNG structures/checksums, and suppress image SQL parameter logging. Foreign-key cascade
deletes attachments for thread/project/workspace deletion. Backups may retain deleted data.
A future object-store adapter can replace this table's binary column behind Snapshots.

Privacy filtering runs before cloning, including descendants; excluded nodes and controls
are omitted rather than blurred. Shadow roots, slots, unsafe SVG subtrees, canvas/video
and frames are omitted. Reviewers must inspect the preview: this cannot identify personal
information in unmarked prose, images or CSS-generated content. No screenshot is inferred
from an anchor or taken automatically later. Web-font scanning is disabled and image
fetches omit credentials/referrers; this trades fidelity for a smaller capture surface.
Requests allow 300 KiB only for snapshot JSON (base64 overhead), while ordinary JSON
requests retain 32 KiB. Raster size is limited to 200 KiB and 1200 pixels per dimension.

Image anchors without stable IDs can use a bounded image source origin/path plus alt
text. Query strings, fragments and URL credentials are excluded; text-capture opt-out
also disables these hints. Selector matches must agree with image identity; ambiguous
fallback matches remain unpinned. Snapshot capture retains the exact selected DOM node
only in memory and checks visibility/exclusions again; it is never sent with the anchor.
