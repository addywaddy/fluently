// Read only the explicitly configured data attribute, never text or form values.
export function customerReference(root, dataset) {
  const selector = dataset.userSelector
  const attribute = dataset.userAttribute || 'data-fluently-user-ref'
  if (!selector) return {state: 'disabled', value: null}
  if (selector.length > 256 || (!attribute.startsWith('data-') || attribute.length < 6 || attribute.length > 69 || /[^a-z0-9_-]/.test(attribute))) return {state: 'invalid', value: null}
  try {
    const matches = root.querySelectorAll(selector)
    if (matches.length === 0) return {state: 'missing', value: null}
    if (matches.length !== 1 || matches[0].closest('[data-feedback-exclude]')) return {state: 'invalid', value: null}
    const value = matches[0].getAttribute(attribute)
    if (value === null || value === '') return {state: 'missing', value: null}
    return value.length <= 200 && !/[^A-Za-z0-9_-]/.test(value) ? {state: 'present', value} : {state: 'invalid', value: null}
  } catch { return {state: 'invalid', value: null} }
}

export function hostIdentityKey(root, dataset) {
  const reference = customerReference(root, dataset)
  // Preserve compatibility for sites that have not enabled DOM references.
  if (!dataset.userSelector) return dataset.sessionKey || ''
  return JSON.stringify([dataset.sessionKey || '', dataset.userSelector, dataset.userAttribute || 'data-fluently-user-ref', reference.state, reference.value])
}
