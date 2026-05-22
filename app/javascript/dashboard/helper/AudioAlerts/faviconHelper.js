let removedFavicons = [];

export const showBadgeOnFavicon = () => {
  const badgedFavicons = document.querySelectorAll('.favicon');
  badgedFavicons.forEach(favicon => {
    const size =
      favicon.getAttribute('sizes') || (favicon.sizes && favicon.sizes[0]);
    if (size) {
      favicon.href = `/favicon-badge-${size}.png`;

      // Force redrawing the badged favicon by re-appending it
      const parent = favicon.parentNode;
      if (parent) {
        const next = favicon.nextSibling;
        parent.removeChild(favicon);
        parent.insertBefore(favicon, next);
      }
    }
  });

  // Find other favicons that do NOT have badge equivalents (e.g., 512x512 or logo thumbnails)
  const allFavicons = document.querySelectorAll('link[rel*="icon"]');
  allFavicons.forEach(favicon => {
    if (!favicon.classList.contains('favicon')) {
      // Remove it from the DOM and save it to our list of removed favicons
      if (favicon.parentNode) {
        removedFavicons.push({
          parent: favicon.parentNode,
          next: favicon.nextSibling,
          element: favicon,
        });
        favicon.parentNode.removeChild(favicon);
      }
    }
  });
};

export const initFaviconSwitcher = () => {
  const resetFavicon = () => {
    const badgedFavicons = document.querySelectorAll('.favicon');
    badgedFavicons.forEach(favicon => {
      const size =
        favicon.getAttribute('sizes') || (favicon.sizes && favicon.sizes[0]);
      if (size) {
        favicon.href = `/favicon-${size}.png`;

        // Force redrawing the original favicon by re-appending it
        const parent = favicon.parentNode;
        if (parent) {
          const next = favicon.nextSibling;
          parent.removeChild(favicon);
          parent.insertBefore(favicon, next);
        }
      }
    });

    // Restore all removed high-resolution or custom branded icons
    while (removedFavicons.length > 0) {
      const item = removedFavicons.shift();
      if (item.parent && !item.element.parentNode) {
        item.parent.insertBefore(item.element, item.next);

        // Force a redraw of the restored favicon
        const parent = item.element.parentNode;
        if (parent) {
          const next = item.element.nextSibling;
          parent.removeChild(item.element);
          parent.insertBefore(item.element, next);
        }
      }
    }
  };

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      resetFavicon();
    }
  });

  window.addEventListener('focus', () => {
    resetFavicon();
  });
};
