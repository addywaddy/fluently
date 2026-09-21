# Fluently browser extensions

Manifest V3 extensions for Chrome, Edge, Firefox and macOS Safari, using the same widget as the website embed.

## Build and install

Run `mix extension.build` to produce all browser packages:

| Browser | Output | Installation |
| --- | --- | --- |
| Chrome | `extension/dist` | Load unpacked at `chrome://extensions` |
| Edge | `extension/builds/edge` | Load unpacked at `edge://extensions` |
| Firefox 128+ | `extension/builds/firefox` | Load `manifest.json` as a temporary add-on |
| Safari 17+ on macOS 14+ | `extension/builds/safari` | Package in an Xcode app as described below |

These are development packages, not published or store-signed releases. Build commands do
not install or launch a browser or grant it website access.

### Chrome and Edge

1. Run `mix extension.build` from the repository (requires Node and the existing esbuild setup).
2. Open the browser's extensions page above, enable Developer mode, choose **Load unpacked**, and select its output directory.
3. Pin Fluently in the browser's toolbar and reload any already-open test pages.

Rebuild and click **Reload** on the extension card after updating it, then reload the website.

### Firefox

Open `about:debugging#/runtime/this-firefox`, choose **Load Temporary Add-on**, and select
`extension/builds/firefox/manifest.json`. Allow access to the sites you want to review,
pin the extension and reload the website. Temporary add-ons disappear when Firefox restarts.
After rebuilding, use **Reload** on the add-on card and reload the website.

Firefox uses an event-page background script and the promise-based `browser` API. Its
stable add-on ID is `fluently@fluently.now`; this does not publish a Mozilla listing.
Permanent installation requires Mozilla signing. Before submitting for signing/publication,
complete the Firefox data-consent implementation and declaration in `fluently-hp5`:
comments, page context, optional snapshots and review credentials are transmitted, so this
must not be declared a no-data extension. Technical/environment data needs the applicable
consent controls. This temporary build is not yet an AMO submission package.

### Safari on macOS

With Xcode selected as the active developer directory, run:

```sh
mix extension.safari
```

This runs Apple's web-extension packager (or its older converter name) and creates
`extension/safari/Fluently/Fluently.xcodeproj`. The project references the generated Safari
resources; rebuilding the extension updates them without regenerating your signing settings.
The generator fixes containing-app/extension bundle IDs and sets macOS 14 as the minimum.

Open that Xcode project, choose your signing team for both targets, and build/run **Fluently**.
Use the containing app to open Safari's extension settings, enable Fluently, grant access
to the relevant sites, then reload them. Signing credentials are yours; none are embedded
in the repository. Signed distribution is tracked in `fluently-hp5`.
This wrapper targets macOS only, not iOS or iPadOS.

For a compile-only check that neither signs nor launches the app:

```sh
xcodebuild -project extension/safari/Fluently/Fluently.xcodeproj \
  -scheme Fluently -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath extension/safari/build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

The unsigned build appears at `extension/safari/build/Build/Products/Debug/Fluently.app`.
It is a build artifact, not a signed distributable installer.

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

Automatic gray/blue detection requires a content script on HTTP/HTTPS pages. Browsers therefore
ask for website access; you can restrict site access through browser settings, but detection only works
where access is granted. Only the top-level document is inspected for installation markers.
No browsing history is uploaded, and inactive pages make no requests to Fluently. Explicitly
activated site configurations are stored locally; the extension does not record page history.

All executable code, including the snapshot library, is packaged locally. There is no remote
script injection, privileged network proxy, or access to cookies through browser extension APIs.
Cross-origin API requests keep the ordinary widget CORS/authentication rules. Snapshot font/image
restrictions still apply. Browser internal pages, protected extension stores, cross-origin frame
contents and closed shadow roots are unsupported. Toolbar icon appearance may be adjusted by
the browser; the popup also reports detection in text.

The organizational account refactor and general DOM metadata configuration remain separate work;
this version uses today's owner/admin authorization and existing capture settings.

## Checks

`mix extension.build && node --test test/extension/*.test.mjs`

Local Playwright and live testing need express permission. CI may run normal browser suites.

Platform references: [Microsoft Edge porting](https://learn.microsoft.com/en-us/microsoft-edge/extensions/developer-guide/port-chrome-extension),
[background script compatibility](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/background),
[Firefox collection consent](https://extensionworkshop.com/documentation/develop/firefox-builtin-data-consent/),
[Apple Safari packaging](https://developer.apple.com/documentation/safariservices/packaging-a-web-extension-for-safari).
