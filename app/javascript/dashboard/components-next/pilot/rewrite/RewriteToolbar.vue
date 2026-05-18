<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store';
import { useRewrite } from 'dashboard/composables/pilot/useRewrite';
import NextButton from 'dashboard/components-next/button/Button.vue';

// MVP scope per design.md D20: this is a menu-driven version that
// rewrites the FULL composer draft (no DOM-level text-selection
// detection). The pilot-utilities spec scenario "floating toolbar
// appears on composer text selection" is deferred — the
// selection-based UX needs hooks into ProseMirror that aren't a
// thin add-on. TODO: convert to a true selection-driven floating
// toolbar once we own the composer editor.
const props = defineProps({
  editorContent: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['rewrite']);

const { t } = useI18n();
const currentAccount = useMapGetter('getCurrentAccount');

const rewrite = useRewrite();
const menuOpen = ref(false);

const isEnabled = computed(() => {
  const account = currentAccount.value || {};
  return Boolean(account.pilot_enabled && account.pilot_rewrite_enabled);
});

const TONES = ['friendly', 'formal', 'concise', 'empathetic', 'assertive'];

const closeMenu = () => {
  menuOpen.value = false;
};

const toggleMenu = () => {
  if (props.disabled || !props.editorContent) return;
  menuOpen.value = !menuOpen.value;
};

const pickTone = async tone => {
  closeMenu();
  if (!props.editorContent) return;
  const result = await rewrite.generate({ text: props.editorContent, tone });
  if (result) emit('rewrite', result);
};
</script>

<template>
  <div
    v-if="isEnabled"
    v-on-click-outside="closeMenu"
    class="relative flex flex-col items-end"
  >
    <NextButton
      ghost
      sm
      icon="i-ph-pencil-line-fill"
      :disabled="disabled || rewrite.loading.value || !editorContent"
      :label="
        rewrite.loading.value
          ? t('PILOT.REWRITE.LOADING')
          : t('PILOT.REWRITE.BUTTON_LABEL')
      "
      class="text-n-violet-9 hover:enabled:!bg-n-violet-3"
      @click="toggleMenu"
    />
    <span v-if="rewrite.error.value" class="text-xs text-n-ruby-9" role="alert">
      {{ rewrite.error.value || t('PILOT.REWRITE.ERROR') }}
    </span>
    <div
      v-if="menuOpen"
      role="menu"
      :aria-label="t('PILOT.REWRITE.TONE_PICKER_TITLE')"
      class="absolute bottom-full right-0 mb-2 min-w-44 rounded-lg border border-n-strong bg-n-solid-3 py-2 shadow-lg z-50"
    >
      <button
        v-for="tone in TONES"
        :key="tone"
        type="button"
        role="menuitem"
        class="flex w-full items-center justify-between gap-3 px-4 py-2 text-left text-sm text-n-slate-12 hover:bg-n-slate-3"
        @click="pickTone(tone)"
      >
        <span>{{ t(`PILOT.REWRITE.TONES.${tone.toUpperCase()}`) }}</span>
      </button>
    </div>
  </div>
</template>
