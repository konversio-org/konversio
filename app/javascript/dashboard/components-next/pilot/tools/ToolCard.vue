<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { vOnClickOutside } from '@vueuse/components';
import { formatDistanceToNow } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  row: { type: Object, required: true },
  isAdmin: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();
const store = useStore();

const isMenuOpen = ref(false);

const closeMenu = () => {
  isMenuOpen.value = false;
};

const toggleMenu = () => {
  isMenuOpen.value = !isMenuOpen.value;
};

const relativeTime = computed(() => {
  const stamp = props.row?.updated_at || props.row?.created_at;
  if (!stamp) return '';
  try {
    return formatDistanceToNow(new Date(stamp * 1000), { addSuffix: true });
  } catch (e) {
    return '';
  }
});

const onEdit = () => {
  closeMenu();
  emit('edit', props.row);
};

const onDelete = () => {
  closeMenu();
  emit('delete', props.row);
};

const onToggleEnabled = async enabled => {
  try {
    await store.dispatch('pilotCustomTools/setEnabled', {
      id: props.row.id,
      enabled,
    });
    useAlert(t('PILOT.TOOLS.DIALOG.TOAST.TOGGLE_SUCCESS'));
  } catch (err) {
    useAlert(t('PILOT.TOOLS.DIALOG.TOAST.TOGGLE_ERROR'));
  }
};
</script>

<template>
  <article
    class="relative flex gap-4 p-4 rounded-xl bg-n-alpha-2 border border-n-weak hover:border-n-slate-5 transition-all duration-200"
  >
    <div class="flex flex-col flex-1 gap-3 min-w-0">
      <header class="flex items-start justify-between gap-3">
        <h3 class="text-heading-sm font-medium text-n-slate-12 leading-snug">
          {{ row.title }}
        </h3>
        <div class="flex items-center gap-3">
          <!-- Switch Enabled (admin-only) -->
          <Switch
            v-if="isAdmin"
            :model-value="row.enabled"
            @change="onToggleEnabled"
          />

          <!-- Ellipsis Action Menu (admin-only) -->
          <div
            v-if="isAdmin"
            v-on-click-outside="closeMenu"
            class="relative flex-shrink-0"
          >
            <button
              type="button"
              class="flex items-center justify-center size-7 rounded-md text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
              @click="toggleMenu"
            >
              <span aria-hidden="true" class="i-lucide-more-vertical size-4" />
            </button>
            <ul
              v-if="isMenuOpen"
              role="menu"
              class="absolute right-0 z-20 mt-1 min-w-32 rounded-lg border border-n-weak bg-n-solid-1 shadow-lg p-1 list-none"
            >
              <li role="none">
                <button
                  type="button"
                  role="menuitem"
                  class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-md text-n-slate-12 hover:bg-n-alpha-1"
                  @click="onEdit"
                >
                  <span aria-hidden="true" class="i-lucide-pencil size-4" />
                  {{ t('PILOT.TOOLS.CARD.EDIT') }}
                </button>
              </li>
              <li role="none">
                <button
                  type="button"
                  role="menuitem"
                  class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-md text-n-ruby-11 hover:bg-n-alpha-1"
                  @click="onDelete"
                >
                  <span aria-hidden="true" class="i-lucide-trash-2 size-4" />
                  {{ t('PILOT.TOOLS.CARD.DELETE') }}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </header>

      <!-- Description truncated to single line -->
      <p class="text-sm text-n-slate-11 truncate max-w-full mb-0">
        {{ row.description }}
      </p>

      <footer
        class="flex flex-wrap items-center justify-between gap-4 pt-1 border-t border-n-weak/50 mt-1"
      >
        <div class="flex flex-wrap items-center gap-2">
          <!-- Auth Badge -->
          <span
            v-if="row.auth_type && row.auth_type !== 'none'"
            class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11 font-medium"
          >
            <span aria-hidden="true" class="i-lucide-lock size-3.5" />
            {{ t('PILOT.TOOLS.CARD.AUTH_BADGE', { type: row.auth_type }) }}
          </span>

          <!-- Last Updated Timestamp -->
          <span
            v-if="relativeTime"
            class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-n-alpha-1 text-xs text-n-slate-11"
          >
            <span aria-hidden="true" class="i-lucide-calendar size-3.5" />
            {{ t('PILOT.TOOLS.CARD.LAST_UPDATED', { time: relativeTime }) }}
          </span>
        </div>
      </footer>
    </div>
  </article>
</template>
