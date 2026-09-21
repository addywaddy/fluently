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

## Shared first-party feedback and independent guest sessions (2026-09-18)

The landing widget is a feedback channel to the Fluently team. It uses one explicitly
configured project with `public_feedback=true`. Customer projects remain invite-only by
default; a public project UUID is never an access credential. `/demo` keeps its URL for
SDK compatibility but is a same-origin cookie/CSRF API with rate limiting. It canonicalizes
landing feedback to the configured project's root URL; local address aliases remain supported.
Production validates the browser Origin against the configured public HTTPS hostname,
not the transport scheme/host/port of an individual reverse-proxied request. CSRF checks
remain mandatory for writes; customer API exact-origin checks are unchanged.

A successful first comment creates a guest `User`, project-scoped `ProjectUser`, and
`GuestReviewSession` atomically with the thread. No Account or workspace is created.
`Account` contains registered credentials and points to a registered User. ProjectUser
holds the project-local display name, kind and optional external reference; it points to
User through an ordinary foreign key. Threads/messages keep their existing author IDs.
The physical `reviewers` table and `reviewer_id` columns remain for migration/API compatibility;
the application schema is now `ProjectUser`. Permissions stay in explicit project membership,
not in the identity kind or customer reference.

Guest capabilities expire after 14 days; expiry removes access, not submitted feedback.
Signup creates an independent registered User/Account/workspace. It never merges guest
identities or claims threads. The browser may retain its independent guest cookie capability
through signup/login; a login on another device cannot recover it. Account authorship applies
only in explicitly owned/administered projects. A guest identity remains unlinked when its
visitor later becomes a project member; staff use a separate membership identity.

Migration backfills registered Users from Account IDs and guest Users from existing reviewer
IDs, preserving all credentials, comments, snapshots and project IDs. Existing feedback
cookie hashes become separate guest capabilities with their original expiry. Legacy anonymous
accounts written during the rolling release also transition lazily after validating the token,
expiry and project; registered account login cannot use this fallback. Registered accounts
created by the old release after migration receive their User lazily. Legacy private demo
projects remain private, with their existing cleanup policy; they are never copied into the
shared inbox. Do not roll back to old signup-claim behavior after accepting new guest sessions.

Thread visibility is checked server-side for every read, reply, status change, deletion and
snapshot request. Pagination filters by author before applying limits. Client-supplied
reviewer/project IDs cannot change the scope. Invitation-based reviewers of public-feedback
projects are also author-scoped, preventing the customer API from bypassing privacy. The
trusted read API key retains project-wide visibility for owner-operated integrations.

Project administration is an explicit workspace membership (currently one account per
workspace). Owners may grant/revoke access to an existing registered account. Admins can
read/reply/resolve/delete feedback and view snapshots; credentials, membership changes and
project deletion remain owner-only. Every request rechecks membership. The landing widget
recognizes account and pilot-owner sessions, so staff can review pins in context. Admin
replies use a project-scoped reviewer; visitor threads keep their original author.

Account secrets are random, hashed in the DB and carried by signed HttpOnly, SameSite
cookies (Secure in production). Signup rotates the secret. Signout revokes it. The pilot
supports one active account session; a new login revokes the previous session. SQLite
IMMEDIATE transactions serialize guest creation and expiry with writes.

Passwords use salted PBKDF2-HMAC-SHA256 with 600,000 iterations through OTP crypto,
following the [OWASP PBKDF2 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
This avoids adding a native password dependency to the existing release. Minimum length
is 15 characters; login and signup are rate-limited. Email is an unverified login identifier,
never a basis for trusting or merging identities. Email verification and password recovery
remain a follow-up before a wider public launch; no email infrastructure is required to
exercise registration locally.

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
from an anchor or taken automatically later. Web-font scanning embeds font families used by the filtered clone. The local vendor patch
reads CSS (including imports) without changing host stylesheets. CSS, font and image
fetches omit credentials/referrers and share an eight-second request deadline. Blocked
fonts fall back to the available font stack; exclusions remain applied before cloning.
Requests allow 300 KiB only for snapshot JSON (base64 overhead), while ordinary JSON
requests retain 32 KiB. Raster size is limited to 200 KiB and 1200 pixels per dimension.

Image anchors without stable IDs can use a bounded image source origin/path plus alt
text. Query strings, fragments and URL credentials are excluded; text-capture opt-out
also disables these hints. Selector matches must agree with image identity; ambiguous
fallback matches remain unpinned. Snapshot capture retains the exact selected DOM node
only in memory and checks visibility/exclusions again; it is never sent with the anchor.

## Browser origin preservation

First-party SDK fetches use `mode: same-origin` and `referrerPolicy: strict-origin`.
The former blocks cross-origin redirects; the latter preserves the browser Origin header
while sending only the site's origin as Referer, never a page path or query. Combining
same-origin mode with no-referrer sends Origin:null in WebKit, as reproduced by the
browser regression test. Customer CORS requests retain no-referrer. The backend still
rejects null/foreign origins and requires CSRF tokens for cookie-authenticated writes.

## Domain claims and runtime authorization

An origin is an allowed deployment location, not verified ownership. The MVP deliberately
has no DNS verification, installation verification or exclusive domain reservation.
Different workspaces may configure projects on the same domain (including agencies and
staging environments). Domain equality never grants project membership, connects a
registered identity or exposes another project's feedback. Public project IDs carry no
read/write authorization. Signed project review sessions, server-side API credentials
and explicit account membership remain the authorization boundaries; CORS/origin checks
are additional browser protections, not authentication. Authorized callers can fabricate
feedback in their own project, and claims about a page are not attestation of provenance.
Cookie-authenticated first-party writes retain CSRF protection. Rate limits use only the
client address supplied by the explicitly trusted single Kamal ingress (see deployment).


## Account reviewing across customer domains (2026-09-18)

Use an explicit top-level redirect and confirmation on Fluently, rather than third-party
cookies or automatic account detection. The SDK creates a random state and SHA-256 PKCE
challenge, keeping the verifier in per-tab session storage. The server validates the return
URL against the project's exact allowed origin, stores a ten-minute connection request in
its signed browser session, and preserves it through login. Confirmation requires CSRF and
matching state. Membership is by project ID, never origin equality.

The return URL is used only for this navigation and temporarily held in the signed
connection cookie, not stored with feedback. It is filtered from application logs. The
SDK also keeps the original URL locally to restore its fragment after validation.

The callback carries only a random 90-second, single-use authorization code and state in
the fragment. The SDK removes those before API access, validates local state/session context,
and exchanges the code plus verifier with credentials omitted. The database transaction
consumes the code atomically. No long-lived account or review credential is put in a URL.
Nonmembers get only a generic guest result; no identity is disclosed to the customer domain.
A guest invitation remains necessary for nonmember review access.

Account review grants store only hashed codes/tokens and bind to the account login hash,
project credential version and exact membership row. Every request checks expiry, current
login and membership, including the linked ProjectUser. Revoke/regrant cannot revive a grant.
Only a successfully authorized grant sets the virtual `account_member` flag that allows
all-thread visibility in public-feedback projects. Existing guest tokens remain guest-scoped.
These grants cannot authenticate to the dashboard and never link earlier guest authors.
Expired grants are pruned hourly; Exit deletes the current account grant.

Host session changes require the documented `data-session-key` and/or
`fluently:identity-changed` integration. The opaque key stays local and is distinct from
future pseudonymous customer-reference metadata. A changed key rejects pending connections,
discards cached credentials and ends the widget; responses after teardown cannot restore it.
The host is trusted code with access to its own session storage, not an adversarial sandbox.


## Pseudonymous DOM references (2026-09-18)

Reuse ProjectUser.external_id for immutable, project-local attribution captured during guest
invitation exchange; never query identity or permissions by this field. A repeated value
creates a separate User/ProjectUser on every exchange. Account review grants ignore the
reference. Guest tokens and visibility remain unchanged; matching a reference cannot recover
private threads or merge a guest with a registered account.

The SDK reads only a configured data attribute from a unique selector after DOM readiness.
It binds session storage and pending PKCE connections to the reference and configuration,
alongside the host session nonce. DOM mutations and pre/post-request checks detect changes;
removal or replacement tears down reviewing rather than silently switching authors. Missing
references permit anonymous reviewing; invalid/ambiguous/excluded configuration blocks it.
When no reference changes, host logout still requires the documented nonce/event integration.

Serialize unverified reference metadata only for owner read keys and validated account-member
sessions. Guest readers never receive it. References are bounded ASCII identifiers, excluded
from request logs, and carry the owning project UUID in API responses. The value itself is
customer-generated HMAC metadata, not a signature Fluently can verify. Signed assertions
would require a separate trust/key-management design and remain a future extension.
## Organizational account foundation (2026-09-21)

Fluently is moving toward the organizational model used by the Rails
Feedstream prototype. `User` will be the global person and authentication
identity; an organizational `Account` will own projects; `AccountMembership`
will carry `owner`, `admin`, or `member` roles; and `ProjectMembership` will
grant ordinary members access to selected projects. Owners and admins can see
all projects in their account, while ordinary members (including invited
clients) need an explicit project assignment. Authorship remains attached to a
User even after access is revoked.

The first transition migration adds `account_memberships` and
`project_memberships`, backfilling registered owners and existing account
project administrators. The current credential-bearing `Accounts.Account`,
`Workspace`, `ProjectAdmin`, and `ProjectUser` schemas remain temporarily so
the deployed application can migrate in stages. Later identity work will move
credentials into `User` and remove the guest/demo compatibility paths.

The second transition migration adds `account_sessions`, binding each hashed
login token to both the registered User and selected Account. Login, logout and
session lookup use this table; the old session columns are still dual-written
until the account/user migration is complete. Review grants continue to bind to
the legacy hash during this compatibility window and will move to the session
record in the next identity step.

Invitations are likewise stored as hashed, seven-day, single-use records. An
invitation names the owning account, intended email, member role and an explicit
list of project IDs. Acceptance verifies the authenticated user's email and
atomically creates the account and project memberships; a link alone grants no
access. Legacy project-admin rows are written only as a transition bridge for
the current reviewer implementation.

Production runs with `FLUENTLY_PRIVATE_ONLY=true` by default. Guest review
sessions and the public/demo cookie API are rejected at their request
boundaries; account review sessions remain available after normal membership
authorization. Tests can temporarily set the flag false while the legacy
tables and compatibility code are being removed in the next migration.

The author migration adds profile fields to `User` and direct `author_user_id`
columns to threads and messages. Registered authors are backfilled, and new
account-authored feedback dual-writes the direct user fields. The legacy
reviewer columns remain readable until guest data is purged and serializers and
ownership checks have moved fully to User.

Migration `20260921203311` purges existing guest, anonymous and pseudonymous
threads, sessions, reviewer identities and anonymous account rows. Registered
feedback, registered users and project configuration are retained. The legacy
tables remain for one compatibility release but production request boundaries
reject new guest writes.

The private runtime cutover resolves review actors from registered `User`
records and account/project memberships through `Fluently.Reviews.Actor`.
New private threads and messages store direct `author_user_id` values. Migration
`20260921205321` removes the guest session table on private deployments. SQLite
cannot rewrite the original non-null reviewer columns during a rolling
migration, so those columns and the unused `project_admins` compatibility table
remain inert until a planned fresh production rebuild; no private request
depends on them.

The Feedstream default-scope approach is not being copied. Fluently will keep
explicit Ecto account/project queries and enforce parent-tenant consistency on
writes. Cross-domain `ReviewGrant` sessions remain the security boundary and
must re-check the live login session, effective membership, origin and project
credential version on every request.
