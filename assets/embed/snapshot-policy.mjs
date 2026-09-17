// Reject sensitive subtrees before html-to-image clones or fetches their contents.
export const privateSelector = '[data-feedback-exclude],[data-feedback-mask],input,textarea,select,[contenteditable]:not([contenteditable="false"]),iframe,canvas,video,audio,object,embed,script,style,link,slot,fluently-feedback'
export function snapshotNodeAllowed(node) {
  if (node.nodeType !== 1) return node.nodeType === 3
  if (node.closest(privateSelector) || node.shadowRoot) return false
  // Upstream deep-clones SVG and can pull <use> definitions from outside the target.
  if (node.tagName.toLowerCase() === 'svg' && node.querySelector(`${privateSelector},use,foreignObject`)) return false
  return true
}
export function snapshotSize(width, height) {
  if (!(width > 0 && height > 0) || width > 8000 || height > 8000) throw new Error('Select a smaller, visible element for a snapshot.')
  const scale = Math.min(1, 1200 / width, 1200 / height)
  return {width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale))}
}
