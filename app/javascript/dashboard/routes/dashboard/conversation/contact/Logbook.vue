<script>
import { useAlert } from 'dashboard/composables';
import PilotLogbookEntriesAPI from 'dashboard/api/pilot/logbook_entries';
import { dynamicTime } from 'shared/helpers/timeHelper';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  props: {
    contactId: {
      type: [String, Number],
      required: true,
    },
  },
  data() {
    return {
      entries: [],
      newEntryContent: '',
      isLoading: false,
      isSubmitting: false,
    };
  },
  watch: {
    contactId: {
      handler: 'fetchEntries',
      immediate: true,
    },
  },
  methods: {
    dynamicTime,
    async fetchEntries() {
      if (!this.contactId) return;
      this.isLoading = true;
      try {
        const response = await PilotLogbookEntriesAPI.list(this.contactId);
        this.entries = response.data;
      } catch (error) {
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.ERROR_FETCH'));
      } finally {
        this.isLoading = false;
      }
    },
    async createEntry() {
      const content = this.newEntryContent.trim();
      if (!content) return;

      this.isSubmitting = true;
      try {
        const response = await PilotLogbookEntriesAPI.create(
          this.contactId,
          content
        );
        this.entries.unshift(response.data);
        this.newEntryContent = '';
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.SUCCESS_CREATE'));
      } catch (error) {
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.ERROR_CREATE'));
      } finally {
        this.isSubmitting = false;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-4 p-4 border-t border-n-slate-3">
    <div class="flex items-center justify-between">
      <h4
        class="text-xs font-semibold uppercase tracking-wider text-n-slate-11 my-0"
      >
        {{ $t('CONTACT_PANEL.LOGBOOK.TITLE') }}
      </h4>
      <span class="i-lucide-book-open text-n-slate-10 text-sm" />
    </div>

    <div
      class="flex flex-col gap-3 max-h-60 overflow-y-auto pr-1 custom-scrollbar"
    >
      <div v-if="isLoading" class="flex justify-center py-4">
        <span class="i-lucide-loader-2 animate-spin text-n-slate-10" />
      </div>
      <div
        v-else-if="entries.length === 0"
        class="text-sm text-n-slate-9 italic py-2 text-center"
      >
        {{ $t('CONTACT_PANEL.LOGBOOK.NO_ENTRIES') }}
      </div>
      <div
        v-for="entry in entries"
        :key="entry.id"
        class="flex flex-col gap-1 p-2 rounded-lg bg-n-slate-2 border border-n-slate-3 group/entry"
      >
        <div class="flex items-center justify-between">
          <span class="text-[10px] font-medium text-n-slate-10 uppercase">
            {{ dynamicTime(entry.created_at) }}
          </span>
        </div>
        <p class="text-sm text-n-slate-12 m-0 break-words leading-relaxed">
          {{ entry.content }}
        </p>
      </div>
    </div>

    <div class="flex flex-col gap-2 mt-1">
      <textarea
        v-model="newEntryContent"
        :placeholder="$t('CONTACT_PANEL.LOGBOOK.PLACEHOLDER')"
        class="w-full p-2 text-sm rounded-lg border border-n-slate-4 bg-white focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none transition-all resize-none min-h-[60px]"
        @keydown.enter.meta.prevent="createEntry"
      />
      <div class="flex justify-end">
        <NextButton
          size="sm"
          :disabled="!newEntryContent.trim() || isSubmitting"
          :loading="isSubmitting"
          @click="createEntry"
        >
          {{ $t('CONTACT_PANEL.LOGBOOK.ADD_ENTRY') }}
        </NextButton>
      </div>
    </div>
  </div>
</template>

<style scoped>
.custom-scrollbar::-webkit-scrollbar {
  width: 4px;
}
.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}
.custom-scrollbar::-webkit-scrollbar-thumb {
  background: var(--n-slate-4);
  border-radius: 10px;
}
.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: var(--n-slate-5);
}
</style>
