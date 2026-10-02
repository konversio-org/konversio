import { flushPromises, mount } from '@vue/test-utils';
import { ARTICLE_EDITOR_MENU_OPTIONS } from 'dashboard/constants/editor';
import { emitter } from 'shared/helpers/mitt';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createStore } from 'vuex';
import FullEditor from './FullEditor.vue';

let view = null;

// The component keeps its EditorView in a module local, so subclass it to grab
// the instance and drive the editor through transactions like a user would.
vi.mock('@chatwoot/prosemirror-schema', async importOriginal => {
  const actual = await importOriginal();
  class TrackedEditorView extends actual.EditorView {
    constructor(...args) {
      super(...args);
      view = this;
    }
  }
  return { ...actual, EditorView: TrackedEditorView };
});

// jsdom has no layout, and ProseMirror measures the caret through Range rects.
const zeroRect = { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 };
Range.prototype.getClientRects = () => [zeroRect];
Range.prototype.getBoundingClientRect = () => zeroRect;
Element.prototype.scrollIntoView = () => {};

// jsdom has no object URLs, and uploads preview through blob: URLs.
let objectUrlCount = 0;
URL.createObjectURL = () => {
  objectUrlCount += 1;
  return `blob:vitest-${objectUrlCount}`;
};
URL.revokeObjectURL = () => {};

const attachImage = vi.fn();
const uploadExternalImage = vi.fn();

const store = createStore({
  actions: {
    'articles/attachImage': (_, payload) => attachImage(payload),
    'articles/uploadExternalImage': (_, payload) =>
      uploadExternalImage(payload),
  },
  getters: {
    getUISettings: () => ({}),
    'globalConfig/get': () => ({ maximumFileUploadSize: 40 }),
  },
});

let wrapper = null;

const mountEditor = (props = {}) => {
  wrapper = mount(FullEditor, {
    props: {
      modelValue: '',
      enabledMenuOptions: ARTICLE_EDITOR_MENU_OPTIONS,
      ...props,
    },
    global: {
      plugins: [store],
      mocks: { $route: { params: { portalSlug: 'handbook' } } },
    },
    attachTo: document.body,
  });
  return wrapper;
};

const type = text => view.dispatch(view.state.tr.insertText(text));

const lastEmittedValue = () => {
  const events = wrapper.emitted('update:modelValue') || [];
  return events.length ? events[events.length - 1][0] : null;
};

const selectFile = async file => {
  const input = wrapper.find('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: [file],
    configurable: true,
  });
  await input.trigger('change');
  await flushPromises();
};

const fileOfSize = sizeInMb => {
  const file = new File(['x'], 'photo.png', { type: 'image/png' });
  Object.defineProperty(file, 'size', { value: sizeInMb * 1024 * 1024 });
  return file;
};

const videoOfSize = sizeInMb => {
  const file = new File(['x'], 'clip.mp4', { type: 'video/mp4' });
  Object.defineProperty(file, 'size', { value: sizeInMb * 1024 * 1024 });
  return file;
};

describe('FullEditor', () => {
  let alerts = [];
  const collectAlert = ({ message }) => alerts.push(message);

  beforeEach(() => {
    alerts = [];
    emitter.on('newToastMessage', collectAlert);
    attachImage.mockResolvedValue('https://cdn.test/photo.png');
    uploadExternalImage.mockResolvedValue('https://cdn.test/remote.png');
  });

  afterEach(() => {
    emitter.off('newToastMessage', collectAlert);
    vi.restoreAllMocks();
    wrapper?.unmount();
    wrapper = null;
    view = null;
  });

  describe('video embed', () => {
    const openEmbedInput = async (trigger = '/') => {
      type(trigger);
      await wrapper.vm.$nextTick();
      wrapper.vm.executeSlashCommand('video');
      await wrapper.vm.$nextTick();
    };

    it('opens the video popover instead of editing the document', async () => {
      mountEditor();
      await openEmbedInput();

      expect(wrapper.findComponent({ name: 'VideoEmbedInput' }).exists()).toBe(
        true
      );
      expect(view.state.doc.textContent).toBe('');
    });

    it('inserts the embed URL as a bare linked paragraph on submit', async () => {
      mountEditor();
      await openEmbedInput();
      wrapper
        .findComponent({ name: 'VideoEmbedInput' })
        .vm.$emit('submit', 'https://youtu.be/dQw4w9WgXcQ');
      await wrapper.vm.$nextTick();

      expect(lastEmittedValue().trim()).toBe('<https://youtu.be/dQw4w9WgXcQ>');
      expect(wrapper.findComponent({ name: 'VideoEmbedInput' }).exists()).toBe(
        false
      );
    });

    it('leaves the document untouched on cancel', async () => {
      mountEditor({ modelValue: 'Hello' });
      await openEmbedInput(' /');
      wrapper.findComponent({ name: 'VideoEmbedInput' }).vm.$emit('cancel');
      await wrapper.vm.$nextTick();

      expect(wrapper.findComponent({ name: 'VideoEmbedInput' }).exists()).toBe(
        false
      );
      expect(view.state.doc.textContent).toBe('Hello ');
    });

    it('routes a video chosen in the popover through the upload pipeline', async () => {
      mountEditor();
      await openEmbedInput();
      wrapper
        .findComponent({ name: 'VideoEmbedInput' })
        .vm.$emit('upload', new File(['x'], 'clip.mp4', { type: 'video/mp4' }));
      await flushPromises();

      expect(attachImage).toHaveBeenCalledWith(
        expect.objectContaining({ portalSlug: 'handbook' })
      );
    });
  });

  describe('file gating', () => {
    it('returns the image bucket for a small image', () => {
      mountEditor();

      expect(wrapper.vm.bucketFor(fileOfSize(1))).toBe('images');
      expect(alerts).toHaveLength(0);
    });

    it('returns the video bucket for an mp4 within the account limit', () => {
      mountEditor();

      expect(wrapper.vm.bucketFor(videoOfSize(20))).toBe('videos');
      expect(alerts).toHaveLength(0);
    });

    it('alerts and rejects an oversized image', () => {
      mountEditor();

      expect(wrapper.vm.bucketFor(fileOfSize(6))).toBeNull();
      expect(alerts).toHaveLength(1);
    });

    it('alerts and rejects an oversized video', () => {
      mountEditor();

      expect(wrapper.vm.bucketFor(videoOfSize(50))).toBeNull();
      expect(alerts).toHaveLength(1);
    });

    it('alerts and rejects an unsupported type', () => {
      mountEditor();

      expect(
        wrapper.vm.bucketFor(
          new File(['x'], 'doc.pdf', { type: 'application/pdf' })
        )
      ).toBeNull();
      expect(alerts).toHaveLength(1);
    });

    it('holds files back with an alert while the parent blocks uploads', async () => {
      mountEditor({ uploadsBlockedMessage: 'article is being created' });
      await selectFile(fileOfSize(1));

      expect(attachImage).not.toHaveBeenCalled();
      expect(alerts).toEqual(['article is being created']);
    });
  });

  describe('pending uploads', () => {
    it('reports a pending mp4 upload until it finishes', async () => {
      mountEditor();
      expect(wrapper.vm.hasPendingUploads()).toBe(false);

      let finishUpload;
      attachImage.mockImplementation(
        () =>
          new Promise(resolve => {
            finishUpload = resolve;
          })
      );
      await selectFile(videoOfSize(1));
      expect(wrapper.vm.hasPendingUploads()).toBe(true);

      finishUpload('https://cdn.test/clip.mp4');
      await flushPromises();
      expect(wrapper.vm.hasPendingUploads()).toBe(false);
    });

    it('reports a failed upload as pending while its error card remains', async () => {
      mountEditor();
      attachImage.mockRejectedValue(new Error('nope'));
      await selectFile(videoOfSize(1));

      const card = view.dom.querySelector('.pm-upload-card');
      expect(card).not.toBeNull();
      expect(wrapper.vm.hasPendingUploads()).toBe(true);

      card.querySelector('[aria-label="Remove"]').click();
      await flushPromises();
      expect(wrapper.vm.hasPendingUploads()).toBe(false);
    });

    it('uploads a selected image and inserts it (regression)', async () => {
      mountEditor();
      await selectFile(fileOfSize(1));

      expect(attachImage).toHaveBeenCalled();
      expect(lastEmittedValue()).toContain('![](https://cdn.test/photo.png)');
    });
  });
});
