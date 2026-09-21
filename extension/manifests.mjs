// Separate manifests keep unsupported browser keys out of each package.
export function manifestFor(base, browser) {
  const manifest = structuredClone(base)
  if (browser === 'firefox') {
    manifest.background = {scripts: ['background.js'], type: 'module'}
    manifest.browser_specific_settings = {gecko: {
      id: 'fluently@fluently.now', strict_min_version: '128.0'
    }}
  } else if (browser === 'safari') {
    manifest.background = {scripts: ['background.js']}
  } else if (!['chrome', 'edge'].includes(browser)) {
    throw new Error(`Unsupported extension target: ${browser}`)
  }
  return manifest
}
