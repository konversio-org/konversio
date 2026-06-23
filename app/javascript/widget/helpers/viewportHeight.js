const VIEWPORT_HEIGHT_VARIABLE = '--cw-widget-viewport-height';

const getViewportHeight = () => {
  return window.visualViewport?.height || window.innerHeight;
};

const updateViewportHeight = () => {
  document.documentElement.style.setProperty(
    VIEWPORT_HEIGHT_VARIABLE,
    `${getViewportHeight()}px`
  );
};

export const initViewportHeightListener = () => {
  updateViewportHeight();

  window.addEventListener('resize', updateViewportHeight);
  window.addEventListener('orientationchange', updateViewportHeight);
  window.visualViewport?.addEventListener('resize', updateViewportHeight);
  window.visualViewport?.addEventListener('scroll', updateViewportHeight);
};
