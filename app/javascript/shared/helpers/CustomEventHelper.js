export const createEvent = ({ eventName, data = null }) => {
  let event;
  if (typeof window.CustomEvent === 'function') {
    event = new CustomEvent(eventName, { detail: data });
  } else {
    event = document.createEvent('CustomEvent');
    event.initCustomEvent(eventName, false, false, data);
  }
  return event;
};

export const dispatchWindowEvent = ({ eventName, data }) => {
  window.dispatchEvent(createEvent({ eventName, data }));

  // Back-compat: also fire the legacy chatwoot:* twin so embeds listening
  // on chatwoot:ready / chatwoot:error / etc. keep working.
  if (typeof eventName === 'string' && eventName.startsWith('konversio:')) {
    const legacyName = eventName.replace('konversio:', 'chatwoot:');
    window.dispatchEvent(createEvent({ eventName: legacyName, data }));
  }
};
