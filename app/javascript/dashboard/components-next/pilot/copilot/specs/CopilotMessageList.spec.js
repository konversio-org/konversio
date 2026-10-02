import { shallowMount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import CopilotMessageList from '../CopilotMessageList.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/app/accounts/1/conversations' }),
}));

const mountList = props =>
  shallowMount(CopilotMessageList, {
    props,
  });

describe('CopilotMessageList.vue', () => {
  describe('suggest-reply quick action', () => {
    it('shows the quick action and emits suggestReply when clicked', async () => {
      const wrapper = mountList({ canSuggestReply: true });
      const button = wrapper
        .findAll('button')
        .find(node => node.text().includes('PILOT.COPILOT.REPLY_SUGGESTION'));

      expect(button).toBeTruthy();
      await button.trigger('click');
      expect(wrapper.emitted('suggestReply')).toBeTruthy();
    });

    it('hides the quick action when the last message is not incoming', () => {
      const wrapper = mountList({ canSuggestReply: false });

      const button = wrapper
        .findAll('button')
        .find(node => node.text().includes('PILOT.COPILOT.REPLY_SUGGESTION'));

      expect(button).toBeUndefined();
    });
  });

  describe('draft rendering', () => {
    const assistantMessage = (content, replySuggestion) => ({
      id: 1,
      message_type: 1,
      message: { content, reply_suggestion: replySuggestion },
    });

    it('renders an insert action for a reply-suggestion draft', async () => {
      const wrapper = mountList({
        messages: [assistantMessage('Draft body', true)],
      });

      const insert = wrapper
        .findAll('button')
        .find(node =>
          node.text().includes('PILOT.COPILOT.REPLY_SUGGESTION.INSERT')
        );

      expect(insert).toBeTruthy();
      await insert.trigger('click');
      expect(wrapper.emitted('insertReply')[0]).toEqual(['Draft body']);
    });

    it('renders discarded and failure messages as plain text without insert action', () => {
      const wrapper = mountList({
        messages: [
          assistantMessage('The suggestion is no longer applicable', false),
        ],
      });

      const insert = wrapper
        .findAll('button')
        .find(node =>
          node.text().includes('PILOT.COPILOT.REPLY_SUGGESTION.INSERT')
        );

      expect(insert).toBeUndefined();
      expect(wrapper.text()).toContain(
        'The suggestion is no longer applicable'
      );
    });
  });
});
