export function reviewerPresentation(identity) {
  const name = typeof identity?.name === 'string' && identity.name.trim()
    ? Array.from(identity.name.trim()).slice(0, 80).join('') : 'Guest'
  const account = identity?.kind === 'account'
  const initials = name.split(/\s+/u).slice(0, 2).map(word => Array.from(word)[0]).join('').toLocaleUpperCase()
  return {name, account, initials, label: `Commenting as ${name}`}
}

export function renderReviewerBadge(node, identity) {
  const view = reviewerPresentation(identity)
  node.className = 'reviewer-identity'
  node.dataset.account = String(view.account)
  node.title = view.account ? 'Fluently account' : 'Project review identity'
  const avatar = node.ownerDocument.createElement('span')
  avatar.className = 'reviewer-avatar'
  avatar.setAttribute('aria-hidden', 'true')
  avatar.textContent = view.initials
  const label = node.ownerDocument.createElement('span')
  label.className = 'reviewer-name'
  label.textContent = view.label
  node.replaceChildren(avatar, label)
}
