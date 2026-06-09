import { config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import i18nMessages from 'dashboard/i18n';
import FloatingVue from 'floating-vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: i18nMessages,
});

config.global.plugins = [i18n, FloatingVue];
config.global.stubs = {
  WootModal: { template: '<div><slot/></div>' },
  WootModalHeader: { template: '<div><slot/></div>' },
  NextButton: { template: '<button><slot/></button>' },
};

if (typeof window !== 'undefined') {
  const localStorageMock = {
    getItem(key) {
      return this[key] === undefined ? null : this[key];
    },
    setItem(key, value) {
      this[key] = String(value);
    },
    removeItem(key) {
      delete this[key];
    },
    clear() {
      Object.keys(this).forEach(key => {
        delete this[key];
      });
    }
  };
  Object.defineProperties(localStorageMock, {
    getItem: { enumerable: false },
    setItem: { enumerable: false },
    removeItem: { enumerable: false },
    clear: { enumerable: false },
  });

  Object.defineProperty(window, 'localStorage', {
    value: localStorageMock,
    configurable: true,
    enumerable: true,
    writable: true
  });
  global.localStorage = localStorageMock;
}
