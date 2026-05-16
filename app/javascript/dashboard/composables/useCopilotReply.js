import { ref, computed } from 'vue';

export function useCopilotReply() {
  const showEditor = ref(false);
  const isGenerating = ref(false);
  const isContentReady = ref(false);
  const generatedContent = ref('');
  const followUpContext = ref(null);
  const isActive = ref(false);
  const isButtonDisabled = computed(() => false);
  const editorTransitionKey = ref(0);

  const reset = () => {
    showEditor.value = false;
    isGenerating.value = false;
    isContentReady.value = false;
    generatedContent.value = '';
    followUpContext.value = null;
  };

  const toggleEditor = () => {};

  const setContentReady = () => {};

  const execute = async () => {};

  const sendFollowUp = async () => {};

  const accept = () => {
    const content = generatedContent.value;
    reset();
    return content;
  };

  return {
    showEditor,
    isGenerating,
    isContentReady,
    generatedContent,
    followUpContext,
    isActive,
    isButtonDisabled,
    editorTransitionKey,
    reset,
    toggleEditor,
    setContentReady,
    execute,
    sendFollowUp,
    accept,
  };
}
