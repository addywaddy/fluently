// Ordinary pins belong to the document's scrolling layer. A fixed overlay
// would trail compositor scrolling until the next JavaScript animation frame.
export function placement(element, origin) {
  let fixed = false
  for (let node = element; node; node = node.parentElement) {
    const position = getComputedStyle(node).position
    if (position === 'fixed' || position === 'sticky') { fixed = true; break }
  }
  const rect = element.getBoundingClientRect()
  // The badge identifies the element, not a word or a percentage of its box.
  // Keep the original click point in the anchor as context, not display geometry.
  const x = rect.left + Math.min(8, rect.width / 2)
  const y = rect.top + Math.min(8, rect.height / 2)
  return {
    position: fixed ? 'fixed' : 'absolute',
    left: fixed ? x : x - origin.left,
    top: fixed ? y : y - origin.top,
    outside: x < 0 || x > innerWidth || y < 0 || y > innerHeight
  }
}
