import {toCanvas} from '../vendor/html-to-image/es/index.js'
import {snapshotNodeAllowed, snapshotSize, snapshotUnavailableReason} from './snapshot-policy.mjs'

export async function captureSnapshot(element) {
  const reason = snapshotUnavailableReason(element)
  if (reason) throw new Error(reason)
  const {width, height} = element.getBoundingClientRect()
  const size = snapshotSize(width, height)
  const canvas = await toCanvas(element, {
    filter: snapshotNodeAllowed,
    width, height, canvasWidth: size.width, canvasHeight: size.height,
    pixelRatio: 1, backgroundColor: '#ffffff',
    // Avoid scanning/fetching stylesheets outside the selected target.
    skipFonts: true, includeQueryParams: true,
    fetchRequestInit: {credentials: 'omit', referrerPolicy: 'no-referrer', signal: AbortSignal.timeout(8000)},
    style: {margin: '0', transform: 'none', animation: 'none', transition: 'none'}
  })
  const data = canvas.toDataURL('image/png')
  if (data.length > 273090) throw new Error('This snapshot is too large. Try a smaller element or post without it.')
  return data
}
