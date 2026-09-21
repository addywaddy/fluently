# Fluently

Figma-style conversations on real websites, with structured context for people and agents.
Phoenix/SQLite monolith, plain CSS management UI, and a standalone ~22 KB JavaScript embed.
The landing design uses plain HTML/CSS; the optional demo uses the embed SDK. The original `designs/` files are unchanged.

## Local development

Requires Elixir 1.17+ / compatible OTP and Node 22+ for SDK tests only.
This build was checked with Elixir 1.20.2 / OTP 29. SQLite is embedded; no database
server is needed. Development and test databases live in ignored `data/` files.
Production uses persistent local storage; see [deployment](docs/deployment.md).
Kamal runs Litestream as a separate backup accessory; configure its bucket and credentials before deployment.

```sh
mix setup
mix fluently.workspace "My studio"
mix phx.server
```

Save the printed **owner key** and sign in at http://localhost:4000/app/login.
Visitors can also register at `/signup` and sign in at `/login` with email and password. Operator-issued owner keys remain supported for pilot workspaces.
Owner keys are bearer credentials: keep them in a password manager, not in the embed.

Run `mix precommit` and `node --test test/embed/*.test.mjs` for checks.
For the Safari-engine regression test: `npm ci --ignore-scripts`,
`npx playwright install webkit`, `mix assets.build`, then `npm run test:browser`.
This exercises actual widget submission in WebKit, including Origin, CSRF and cookies.
GitHub Actions runs on pushes to `main`, pull requests targeting `main`, and manual dispatch.
It checks formatting and compilation warnings, runs backend/SDK tests, and builds the
production Docker image (including assets and the release). Pushes to `main` deploy through Kamal after both checks pass; deployment uses GitHub secrets.
Pull request checks do not deploy, and CI never applies Terraform.
Run `mix assets.build` after editing `assets/embed/`; the normal development watcher watches app.js only.

## Create a project and install

Chrome, Edge, Firefox and macOS Safari reviewers can also use the [Fluently extension](extension/README.md): its toolbar
icon turns blue when Fluently is detected, and **Start Fluently** launches the review flow
without a special URL. Build it with `mix extension.build` and load `extension/dist` as an
unpacked Chrome extension. Other packages are in `extension/builds`; `mix extension.safari`
creates the Safari Xcode wrapper. See the extension guide for temporary Firefox installation
and Safari signing. It can run the bundled widget on a configured project site without a snippet.

1. Create a project in `/app`, supplying its exact origin (e.g. `https://staging.example.com`, no trailing slash). HTTP is permitted for localhost testing only.
2. Copy the snippet onto that website:

```html
<script defer src="https://feedback.example.com/embed.js" data-project="PUBLIC_PROJECT_UUID"></script>
```

3. Save the **review link** and **read-only API key** shown once after creation. They are distinct from the public project UUID.
4. Send reviewers the review link. Its fragment contains an unguessable invitation, removed by the SDK before it makes API requests. It expires after 14 days. Change the path before the fragment to review a particular page.
5. Reviewers choose a display name and click the circular Fluently logo at the bottom right to enable commenting. Right-click an element and choose **Add comment**, or click **Add comment** in the toolbar and then select an element. Click a numbered pin to reply or resolve. The thread list includes hidden targets and a resolved filter.

Commenting starts off. The circular logo is grayscale while off and blue while on; the toolbar slides out to its left, aligned with the logo. On narrow screens, swipe the toolbar horizontally to reach additional controls. Turning it off hides pins and tools and restores ordinary page interactions. While on, ordinary left-clicks still navigate unless toolbar element selection is active. Escape dismisses the context menu or cancels selection/a draft; when no such UI is open it turns commenting off. Clicking outside, scrolling or resizing dismisses the menu. Shift + right-click keeps the native browser menu; editable and excluded areas are never given a Fluently menu.

In the thread panel, **Delete reply** removes one reply you wrote. **Delete thread** on your opening comment removes the entire conversation and pin, including replies, after explicit confirmation. Deletion is permanent.

Guests share project-wide review access; there are no individual guest roles in V1. Signed review sessions last 24 hours and persist in sessionStorage for that tab. **Exit** clears the local session. Rotating project keys revokes all existing invitations/sessions and the old API key. Owner sessions last 12 hours.

On customer websites, no invitation/session means no widget or feedback requests. Merely viewing the public snippet gives no read/write access. The host website must be trusted: its scripts can access same-page session storage. The SDK does not bypass host-site authentication.

## Review with a Fluently account

Project owners can choose **Edit project** from the project page to change its name or
website origin. A name-only change preserves credentials. Changing the origin issues a
new review link and read-only API key and invalidates existing review sessions; save the
new credentials shown after saving. The project ID and embed snippet remain unchanged.
Existing feedback keeps its original page URLs. Invited project admins cannot edit these
owner-only settings.

Project owners and explicitly added admins can use **Review on website with Fluently**
in the project dashboard, or **Continue with Fluently** in the widget. This opens Fluently
in the same tab, asks for login if needed, and asks you to confirm your identity before
returning to the customer website. Third-party cookies are not required. A project member
comments with their account's display name; a nonmember returns to guest reviewing using
their invitation, without sharing their account name, email or account ID. Earlier guest
comments are never merged. The toolbar and composer show your name and initials avatar.
Account reviewers can select **All reviews** or **My reviews** in the widget. My reviews
means threads started under that project's Fluently account identity, including replies
within those threads; earlier guest threads remain separate. The filter also applies to
pins and the thread list, alongside the existing open/resolved filter. It does not change
project permissions. API lists accept `view=all` (default) or `view=mine`; owner read keys
have no personal author identity, so `view=mine` returns an empty list.

Account review sessions last up to 24 hours. Fluently logout, another login, account-session
expiry, credential rotation, membership removal, or **Exit** revoke access. An account
review session never grants dashboard access. The host page and its scripts must be trusted,
just as for invitation tokens.

On customer sites with login/logout or account switching, supply an opaque, non-sensitive
`data-session-key` on the embed script. Change it whenever the host login session changes,
including logout. The SDK checks it across reloads and observes changes in SPAs. It stays
in browser session storage and is not sent to Fluently; it is not a customer identifier or
authorization credential. Sites without host accounts can omit it.

```html
<script defer src="https://fluently.now/embed.js"
  data-project="PUBLIC_PROJECT_UUID" data-session-key="OPAQUE_HOST_SESSION_NONCE"></script>
```

For an immediate logout/account-switch notification, dispatch this **before** replacing
host-user content (also change the session key for subsequent page loads):

```javascript
window.dispatchEvent(new Event('fluently:identity-changed'));
```

This clears local review state and attempts server revocation of account review access.
If offline, local credentials are still removed; server expiry/login revocation remains
in force. Arbitrary host authentication changes cannot be inferred without this integration.
Reopen the review link to start a new session.

## Pseudonymous customer references

To match guest feedback to your own customers, render a project-specific opaque reference
into one explicit data attribute. The embed reads only that attribute; it never reads
text, form values, or arbitrary DOM content for identity.

```html
<meta id="fluently-customer" data-customer-ref="SERVER_GENERATED_HMAC">
<script defer src="https://fluently.now/embed.js"
  data-project="PUBLIC_PROJECT_UUID"
  data-user-selector="#fluently-customer"
  data-user-attribute="data-customer-ref"
  data-session-key="OPAQUE_HOST_SESSION_NONCE"></script>
```

`data-user-selector` accepts a CSS selector, including an element ID, with exactly one match.
`data-user-attribute` defaults to `data-fluently-user-ref` and must name a `data-*` attribute.
References accept 1–200 ASCII letters, digits, underscores or hyphens (hex or base64url).
The selector is limited to 256 characters. Excluded areas are never read. Invalid,
ambiguous or excluded configuration blocks reviewing until corrected; absent elements
or empty/missing attributes start an ordinary guest session without a reference.

The reference is fixed when the guest exchanges an invitation. Adding, changing or
removing it ends the current session, including cached credentials and pending account
connections. Reopen an invitation to review again. Use `data-session-key` and the logout
hook above even when a reference is absent: Fluently cannot infer a host login change
that produces no DOM/session signal. Account-backed project members keep account authorship;
the customer reference is not attached to their registered identity.

Generate the reference **on your server**, using HMAC-SHA256 with a company-held secret
and project-specific input. For example, in Elixir:

```elixir
# CUSTOMER_REFERENCE_SECRET is a random 32-byte key encoded as base64.
# Generate once outside the request path and keep it in your server's secret store.
secret = System.fetch_env!("CUSTOMER_REFERENCE_SECRET") |> Base.decode64!()
reference =
  :crypto.mac(:hmac, :sha256, secret, "fluently:v1:" <> project_id <> ":" <> customer_uuid)
  |> Base.url_encode64(padding: false)
```

Use canonical UUIDs for both inputs. Never put the secret or raw customer UUID in the
snippet or send them to Fluently. Your company can recompute references to match its
customers; different project IDs produce different references. Rotating the secret changes
the references and ends existing browser review sessions when the new value appears.
A plain hash of an identifier offers less protection against guessing than a keyed HMAC.

These values are **pseudonymous, unverified metadata**, not authentication: anyone with DOM
access can copy or replace them. They never recover old threads, merge users, grant access,
or establish identity on another device. Each invitation exchange still creates a new guest
identity. Pseudonymous data may still be personal data for your company.

Owner read API keys and authenticated project-member review sessions receive
`messages[].author.external_ref` when present:

```json
{"value":"opaque-reference","verified":false,"scope":"PROJECT_UUID"}
```

Guest API responses omit this field, even for collaborative projects. The session endpoint
accepts optional `external_ref`; supplying it without a valid invitation grants no access.
Signed assertions for trusted continuity may be added later; unsigned references do not
silently enable that behavior.

## Dogfooding on Fluently

The landing widget sends feedback to the **Fluently** project for signed-in Fluently users.
Invited project members see the projects assigned to them; owners and admins see all feedback
in their account. The inbox supports replies, resolve/reopen, snapshots, deletion and
pagination.
The inbox supports replies, resolve/reopen, snapshots, deletion and pagination. Owners can
add or revoke admins by their existing registered account email; admins cannot manage
credentials, grant access or delete the project.

Invitations are tied to an intended email and selected projects. Acceptance creates the
account and project memberships atomically; a link alone grants no access. Login sessions
last 30 days and are bound to both the user and selected account. The legacy guest session
tables remain only as a migration compatibility layer and are rejected in production by
default. Email verification and password recovery are not implemented yet.

`FLUENTLY_PROJECT_ID` selects the first-party project. A missing project fails closed.
`FLUENTLY_PRIVATE_ONLY=true` (the production default) rejects guest review sessions and
the public/demo cookie API. Set it to `false` only for a controlled compatibility window.
`FLUENTLY_DEMO_ENABLED=false` disables the landing widget and API entirely.

## Anchors and privacy

Use stable semantic IDs for the best results:

```html
<button data-feedback-id="checkout-continue">Continue</button>
<section data-feedback-exclude>Private information</section>
```

Pins mark the target’s top-right corner with a fixed 8px inset (clamped inside tiny elements), so resizing or text wrapping does not shift them across its contents. Hovering or focusing a pin highlights its target. Selecting a comment keeps the blue target boundary visible while its panel is open, including during scrolling and resizing. Multiple comments on the same visible element share a badge that opens a thread chooser. Existing comments use this placement too; their original relative click points remain in API context.

Desktop and mobile equivalents may share a feedback ID. Exactly one visible match is required.
Hidden, missing, ambiguous, excluded, and offscreen targets have no visible pin; their threads remain in the list. A DOM selector is stored as a fallback, never absolute page coordinates. Avoid recycled DOM IDs for different records.

The embed records a versioned `web/dom` anchor, relative point, viewport, scroll position, browser family, page origin/path, guest identity and messages. Query strings and fragments are dropped. If there is no stable ID, it captures at most 160 characters of the selected target’s text and ARIA label for conservative matching. Set `data-capture-text="false"` on the script to disable that fallback; use explicit IDs in that mode.

No form values, cookies, storage contents, DOM dumps or full user-agent strings are collected automatically. Element snapshots are optional and previewed before posting. Form controls, editable areas, excluded ancestors and containers with sensitive descendants are not selectable. Paths, IDs, selected text and reviewer-written comments may still contain personal data: mark sensitive areas and avoid secrets in feedback. The server validates and allowlists context fields. Owners can delete individual threads or whole projects (including reviewers). Unclaimed demos have automatic 14-day retention; other project retention is manual. Deletion is not backup erasure.

Shadow DOM prevents normal CSS collisions. Only feedback mode intercepts host selection events. The widget polls every 15 seconds and notices pathname changes without patching history APIs. Query-driven/hash-driven page states share the same page; cross-origin iframes, closed shadow roots and canvas internals are not supported. Host CSP must permit `script-src` and `connect-src` to the service, and the widget’s inline styles (or a `style-src` nonce matching `data-style-nonce` on the snippet). See architecture notes before using on sensitive websites.

## Element snapshots

Select an element, choose **Attach element snapshot**, inspect the preview, then post.
Unsupported or private targets show a disabled snapshot button with an explanation;
commenting remains available. You can remove the preview before posting. Reopen the thread and choose **View element
snapshot** to see the historical image. Capture/upload failure does not lose the comment;
a failed upload offers a retry while the thread stays open.

Snapshots omit `data-feedback-exclude`, `data-feedback-mask`, form controls, editable
content, embedded documents, canvas/video, and shadow-root contents. Exclusions remove
subtrees, so spacing can change. Do not rely on this as automatic personal-data detection:
ordinary text and images can contain private information. Always check the preview.
Set `data-screenshots="false"` on the embed to hide capture; `data-capture-text="false"`
also disables it. These are client capture settings, not server authorization rules.

This uses vendored [html-to-image 1.11.13](https://github.com/bubkoo/html-to-image),
which reconstructs a selected element, rather than recording browser pixels. Fonts can
fall back, and cross-origin assets, complex CSS, SVG references and browser differences
can affect the result. Web-font scanning embeds fonts used by the captured element where accessible. Stylesheets
are read without changing the host page; blocked fonts fall back gracefully. Asset fetches omit
credentials and referrers. Host CSP must allow `img-src data:` for capture and display.
The anchor remains responsible for pin positioning.

One immutable PNG per thread, up to 200 KiB and 1200 × 1200 pixels, is stored privately
in SQLite. It shares project authorization, deletion and retention, and existing database
backups. No public image URLs or additional storage credentials are needed.

## API

Project API keys are read-only and intended for server-side tools:

```sh
curl -H "Authorization: Bearer $FLUENTLY_API_KEY" \
  'https://feedback.example.com/api/projects/PROJECT_UUID/comments?status=open'
```

- `GET /api/projects/:id/comments?status=open&page=ENCODED_ORIGIN_AND_PATH&offset=0`
- `GET /api/projects/:id/comments/:thread_id`
- `POST /api/projects/:id/sessions` — `{token: REVIEW_INVITATION, name: DISPLAY_NAME}` → signed review token.
- `POST /api/projects/:id/comments` — review session required; `{body, page, anchor, context}`.
- `POST /api/projects/:id/comments/:thread_id/replies` — review session; `{body}`.
- `PATCH /api/projects/:id/comments/:thread_id` — review session; `{status: "open" | "resolved"}`.
- `DELETE /api/projects/:id/comments/:thread_id/messages/:message_id` — author’s review session required. Deleting the initial message deletes the thread and replies; deleting a reply preserves the thread. Returns `{deleted_thread: boolean, data: thread | null}`. Each message includes a caller-specific `can_delete` flag; read-only keys always receive false.

Use `Authorization: Bearer …` for both read keys and signed review sessions. Lists return
`{data: [...], next_offset: number | null}` in creation order, 100 threads per page.
Each thread includes IDs, page, status, timestamps, versioned anchor/context and messages with author ID/name/kind.
Errors return `{error: {message}}` with 401/403/404/422/429. The embed displays up to 1,000 threads per page;
the API is paginated. See `test/support/feedback_fixtures.ex` for a complete create payload.

The landing demo uses separate, same-origin `/demo/comments` endpoints with the same
thread lifecycle payloads. These require the browser cookie and CSRF token for writes;
they derive the project from server configuration and accept no project selection from the client.
Every thread/snapshot operation enforces author visibility; owners and project admins have full access.
For public-feedback projects, invitation sessions also see only threads they started; the trusted
read-only API key retains full project visibility.
The public project ID never grants access to a private demo or customer project.

Snapshot API: `POST /api/projects/:id/comments/:thread_id/snapshot` accepts
`{"data_url":"data:image/png;base64,..."}` from the thread author using the review bearer
token. `GET` on the same path returns `{data: {data_url, width, height, created_at}}` to
project reviewers or read-only API keys. Retries preserve the original attachment.
Thread/list responses contain snapshot dimensions/time or null, never image bytes.
The landing widget uses `/demo/comments/:thread_id/snapshot` with its cookie/CSRF session.

## Architecture and deployment

`Fluently.Accounts` owns registered credentials, account sessions and legacy demo cleanup;
`Fluently.GuestReviews` owns independent first-party guest capabilities;
`Fluently.Feedback` owns workspace/project credentials and reviewer sessions;
`Fluently.Threads` owns scoped conversations; `Fluently.Reviews.Anchor` validates context.
`assets/embed/anchor.mjs` handles DOM capture/resolution independently of widget UI.
Production exceptions and process crashes are reported to Sentry with minimized request
context; local development and tests do not send reports. Source context is packaged
automatically with releases.
No MCP, billing or agent execution is included. Decisions: [docs/architecture.md](docs/architecture.md).
Kamal and release instructions: [docs/deployment.md](docs/deployment.md). Use a single app instance for the pilot’s in-memory rate limiter.

A separate-origin test host is in `test/fixtures/host/index.html`. Copy it to a temporary directory,
replace `__PROJECT_ID__` with a project configured for `http://localhost:4100`, then serve that directory
with `python3 -m http.server 4100 --bind 127.0.0.1 --directory PATH`. Open its review link to test
reloads, layout shifts, the responsive menu, excluded areas and SPA pathname changes.
