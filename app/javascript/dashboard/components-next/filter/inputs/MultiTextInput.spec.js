import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import MultiTextInput from './MultiTextInput.vue';

const mountComponent = (modelValue = []) =>
  mount(MultiTextInput, {
    props: { modelValue, 'onUpdate:modelValue': () => {} },
  });

describe('MultiTextInput', () => {
  it('commits a value containing a comma as a single chip', async () => {
    const wrapper = mountComponent();

    await wrapper.find('input').setValue('hello, world');
    await wrapper.find('input').trigger('keydown.enter');

    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual([
      'hello, world',
    ]);
  });

  it('removes only the clicked chip', async () => {
    const wrapper = mountComponent(['a', 'b']);

    await wrapper.findAll('span.i-lucide-x')[0].trigger('click');

    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual(['b']);
  });
});
