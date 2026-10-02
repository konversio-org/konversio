import { shallowMount } from '@vue/test-utils';
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import SuggestionReviewDialog from '../SuggestionReviewDialog.vue';
import PilotFaqSuggestionsAPI from 'dashboard/api/pilot/faqSuggestions';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('vue-router');

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => 42),
}));

vi.mock('dashboard/api/pilot/faqSuggestions', () => ({
  default: { show: vi.fn() },
}));

const suggestion = {
  id: 7,
  question: 'How do I cancel?',
  answer: 'From Settings > Billing.',
};

const observations = [
  {
    id: 1,
    generated_question: 'How do I cancel?',
    conversation: { id: 100, display_id: 55 },
  },
];

const mount = () =>
  shallowMount(SuggestionReviewDialog, {
    props: { suggestion },
    global: {
      stubs: { Dialog: true, Input: true, Button: true },
    },
  });

describe('SuggestionReviewDialog.vue', () => {
  const pushMock = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    useRouter.mockReturnValue({ push: pushMock });
    PilotFaqSuggestionsAPI.show.mockResolvedValue({ data: { observations } });
  });

  it('loads source conversations for the suggestion', async () => {
    const wrapper = mount();
    await wrapper.vm.$nextTick();
    await vi.waitFor(() => {
      expect(wrapper.vm.sources).toEqual(observations);
    });

    expect(PilotFaqSuggestionsAPI.show).toHaveBeenCalledWith(7);
  });

  it('emits save with trimmed values', async () => {
    const wrapper = mount();
    wrapper.vm.question = '  Edited question?  ';
    wrapper.vm.answer = '  Edited answer. ';

    wrapper.vm.onSave();

    expect(wrapper.emitted('save')).toEqual([
      [{ id: 7, question: 'Edited question?', answer: 'Edited answer.' }],
    ]);
  });

  it('does not emit save when question or answer is blank', () => {
    const wrapper = mount();
    wrapper.vm.question = '   ';
    wrapper.vm.answer = '';

    wrapper.vm.onSave();

    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.vm.questionError).toBe(
      'PILOT.FAQ_SUGGESTIONS.DIALOG.QUESTION_REQUIRED'
    );
    expect(wrapper.vm.answerError).toBe(
      'PILOT.FAQ_SUGGESTIONS.DIALOG.ANSWER_REQUIRED'
    );
  });

  it('emits approve with the edited values', () => {
    const wrapper = mount();
    wrapper.vm.answer = 'Corrected answer.';

    wrapper.vm.onApprove();

    expect(wrapper.emitted('approve')).toEqual([
      [{ id: 7, question: 'How do I cancel?', answer: 'Corrected answer.' }],
    ]);
  });

  it('emits dismiss for the suggestion', () => {
    const wrapper = mount();

    wrapper.vm.onDismiss();

    expect(wrapper.emitted('dismiss')).toEqual([[{ id: 7 }]]);
  });

  it('deep-links a source row to its conversation', async () => {
    const wrapper = mount();

    wrapper.vm.goToConversation(observations[0]);

    expect(pushMock).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: 42, conversation_id: 55 },
    });
  });
});
