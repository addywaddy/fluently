// Ordinary pins belong to the document's scrolling layer. A fixed overlay
// would trail compositor scrolling until the next JavaScript animation frame.
export function placement(element, point, origin) {
  let fixed = false
  for (let node = element; node; node = node.parentElement) {
    const position = getComputedStyle(node).position
    if (position === 'fixed' || position === 'sticky') { fixed = true; break }
  }
  const rect = element.getBoundingClientRect()
  const x = rect.left + rect.width * point.x
  const y = rect.top + rect.height * point.y
  return {
    position: fixed ? 'fixed' : 'absolute',
    left: fixed ? x : x - origin.left,
    top: fixed ? y : y - origin.top,
    outside: x < 0 || x > innerWidth || y < 0 || y > innerHeight
  }
}
