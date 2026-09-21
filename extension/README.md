# Fluently for Chrome

An unpacked Manifest V3 extension using the same widget as the website embed.

## Build and install

1. Run `mix extension.build` from the repository (requires Node and the existing esbuild setup).
2. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select `extension/dist`.
3. Pin Fluently in Chrome's toolbar and reload any already-open test pages.

Rebuild and click **Reload** on the extension card after updating it, then reload the website.
This is a local development build, not a published Chrome Web Store listing.

## Review

The toolbar icon is **blue** when a valid Fluently embed or widget is detected and **gray** otherwise.
Blue means available, not authorized. Click the icon, then **Start Fluently**. If necessary,
choose **Continue with Fluently**, sign in and confirm your identity. The backend still checks
project membership and the exact website origin. No special URL fragment is needed.

For the local test page, use service `http://localhost:4000`, a project created in that local
Fluently instance, and project website origin `http://localhost:8000`.

Without a snippet, enter the service origin and project UUID from your dashboard's embed
snippet in the popup. Configuration is remembered per website origin on this device.
This initial version does not fetch a list of your projects. Multiple detected installations
appear in a selector; an already-running widget is reused instead of creating a second one.

The existing widget handles sign-in, expiry/revocation, pins, replies, snapshots and SPA
pathname changes. Review credentials remain in the website's per-tab session storage,
as with the normal embed; host pages must be trusted. Configuration (not credentials) is
stored in extension local storage. Exit removes the remembered extension configuration.
Ordinary reloads restore a valid review session; no new privileges are granted by the extension.

## Permissions and limitations

Automatic gray/blue detection requires a content script on HTTP/HTTPS pages. Chrome therefore
asks for website access; you can restrict site access through Chrome, but detection only works
where access is granted. Only the top-level document is inspected for installation markers.
No browsing history is uploaded, and inactive pages make no requests to Fluently. Explicitly
activated site configurations are stored locally; the extension does not record page history.

All executable code, including the snapshot library, is packaged locally. There is no remote
script injection, privileged network proxy, or access to cookies through Chrome APIs.
Cross-origin API requests keep the ordinary widget CORS/authentication rules. Snapshot font/image
restrictions still apply. Chrome internal pages, the Web Store, cross-origin frame contents and
closed shadow roots are unsupported. Safari and Firefox packaging is outside this version.

The organizational account refactor and general DOM metadata configuration remain separate work;
this version uses today's owner/admin authorization and existing capture settings.

## Checks

`mix extension.build && node --test test/extension/*.test.mjs`

Local Playwright and live testing need express permission. CI may run normal browser suites.
