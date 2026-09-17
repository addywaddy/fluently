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
GitHub Actions runs on pushes to `main`, pull requests targeting `main`, and manual dispatch.
It checks formatting and compilation warnings, runs backend/SDK tests, and builds the
production Docker image (including assets and the release). CI needs no production
secrets and does not publish images, apply Terraform, or deploy.
Run `mix assets.build` after editing `assets/embed/`; the normal development watcher watches app.js only.

## Create a project and install

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

## Dogfooding on Fluently

The landing demo is enabled by default locally and in production. No project setup,
ID, or invitation is required. Only the landing route includes the embed; login and
project-management screens do not. Set `FLUENTLY_DEMO_ENABLED=false` to disable it.
Ordinary visitors can click the floating Fluently logo without an invitation or name prompt.
Their first successful comment creates an anonymous account and a private demo project.
A signed HttpOnly, SameSite cookie remembers their session across reloads. Each visitor
sees only their own demo. The private project uses the origin serving the landing page.

**Save my demo** opens `/signup`. Registration upgrades the same account, preserves its
comments, and unlocks project creation in `/app`. A new session replaces the anonymous
session. `/login` restores a registered account on another device. Login opens that
account’s existing demo; it does not merge a different anonymous demo. Currently one
active account session is supported: signing in elsewhere revokes the earlier session.
Email addresses are unverified identifiers; verification and password recovery flows
are not implemented yet. Production email delivery is configured for Resend using
`RESEND_API_KEY` and `MAIL_FROM`; see the deployment guide. Development keeps the local
Swoosh mailbox at `/dev/mailbox`.

Unclaimed demos expire 14 days after creation and are deleted by an hourly cleanup
worker (up to 500 per run). Clearing cookies loses access to an unclaimed demo. Signup
removes its expiry. Registered sessions last 30 days; sign-out revokes them server-side.

Run `mix phx.server` locally; the same demo flow runs at `https://fluently.now` in
production. Existing private demo projects and comments remain intact. Customer embeds
still require a public project ID and an authorized reviewer session.

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
can affect the result. Web-font stylesheet scanning is disabled; asset fetches omit
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
they derive the project from the account and accept no project selection from the client.
The public project ID never grants access to a private demo or customer project.

Snapshot API: `POST /api/projects/:id/comments/:thread_id/snapshot` accepts
`{"data_url":"data:image/png;base64,..."}` from the thread author using the review bearer
token. `GET` on the same path returns `{data: {data_url, width, height, created_at}}` to
project reviewers or read-only API keys. Retries preserve the original attachment.
Thread/list responses contain snapshot dimensions/time or null, never image bytes.
The private demo uses `/demo/comments/:thread_id/snapshot` with its cookie/CSRF session.

## Architecture and deployment

`Fluently.Accounts` owns anonymous-to-registered identities, account sessions and demo retention;
`Fluently.Feedback` owns workspace/project credentials and reviewer sessions;
`Fluently.Threads` owns scoped conversations; `Fluently.Feedback.Anchor` validates context.
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
