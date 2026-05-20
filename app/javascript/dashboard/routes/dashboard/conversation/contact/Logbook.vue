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
      editingId: null,
      editingContent: '',
      busyId: null,
      pendingDeleteId: null,
    };
  },
  computed: {
    showDeleteModal() {
      return this.pendingDeleteId !== null;
    },
  },
  watch: {
    contactId: {
      handler: 'fetchEntries',
      immediate: true,
    },
  },
  methods: {
    formatTime(isoString) {
      return dynamicTime(Math.floor(new Date(isoString).getTime() / 1000));
    },
    isEdited(entry) {
      return entry.updated_at && entry.updated_at !== entry.created_at;
    },
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
    startEdit(entry) {
      this.editingId = entry.id;
      this.editingContent = entry.content;
    },
    cancelEdit() {
      this.editingId = null;
      this.editingContent = '';
    },
    async saveEdit() {
      const content = this.editingContent.trim();
      if (!content || this.busyId) return;

      const id = this.editingId;
      this.busyId = id;
      try {
        const response = await PilotLogbookEntriesAPI.update(id, content);
        const idx = this.entries.findIndex(e => e.id === id);
        if (idx !== -1) this.entries.splice(idx, 1, response.data);
        this.editingId = null;
        this.editingContent = '';
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.SUCCESS_UPDATE'));
      } catch (error) {
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.ERROR_UPDATE'));
      } finally {
        this.busyId = null;
      }
    },
    requestDelete(entry) {
      this.pendingDeleteId = entry.id;
    },
    closeDeleteConfirm() {
      this.pendingDeleteId = null;
    },
    async confirmDelete() {
      const id = this.pendingDeleteId;
      this.pendingDeleteId = null;
      if (!id) return;

      this.busyId = id;
      try {
        await PilotLogbookEntriesAPI.destroy(id);
        this.entries = this.entries.filter(e => e.id !== id);
        if (this.editingId === id) this.cancelEdit();
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.SUCCESS_DELETE'));
      } catch (error) {
        useAlert(this.$t('CONTACT_PANEL.LOGBOOK.ERROR_DELETE'));
      } finally {
        this.busyId = null;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-4 p-4 border-t border-n-slate-3">
    <div class="flex flex-col gap-1">
      <div class="flex items-center justify-between">
        <h4
          class="text-xs font-semibold uppercase tracking-wider text-n-slate-11 my-0"
        >
          {{ $t('CONTACT_PANEL.LOGBOOK.TITLE') }}
        </h4>
        <span class="i-lucide-book-open text-n-slate-10 text-sm" />
      </div>
      <p class="text-xs text-n-slate-10 m-0 leading-snug">
        {{ $t('CONTACT_PANEL.LOGBOOK.SUBTITLE') }}
      </p>
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
        :class="{ 'opacity-50 pointer-events-none': busyId === entry.id }"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="text-[10px] font-medium text-n-slate-10 uppercase">
            {{ formatTime(entry.updated_at || entry.created_at) }}
            <span v-if="isEdited(entry)" class="normal-case text-n-slate-9">
              · {{ $t('CONTACT_PANEL.LOGBOOK.EDITED') }}
            </span>
          </span>
          <div
            v-if="editingId !== entry.id"
            class="flex gap-1 opacity-0 group-hover/entry:opacity-100 transition-opacity"
          >
            <button
              type="button"
              :title="$t('CONTACT_PANEL.LOGBOOK.EDIT')"
              class="i-lucide-pencil text-n-slate-10 hover:text-n-slate-12 text-xs"
              @click="startEdit(entry)"
            />
            <button
              type="button"
              :title="$t('CONTACT_PANEL.LOGBOOK.DELETE')"
              class="i-lucide-trash-2 text-n-slate-10 hover:text-n-ruby-9 text-xs"
              @click="requestDelete(entry)"
            />
          </div>
        </div>
        <template v-if="editingId === entry.id">
          <textarea
            v-model="editingContent"
            class="w-full p-2 text-sm rounded-lg border border-n-slate-4 bg-n-alpha-3 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none transition-all resize-none min-h-[60px]"
            @keydown.enter.meta.prevent="saveEdit"
            @keydown.escape.prevent="cancelEdit"
          />
          <div class="flex justify-end gap-2 mt-1">
            <NextButton
              size="xs"
              variant="ghost"
              :disabled="busyId === entry.id"
              @click="cancelEdit"
            >
              {{ $t('CONTACT_PANEL.LOGBOOK.CANCEL') }}
            </NextButton>
            <NextButton
              size="xs"
              :disabled="!editingContent.trim() || busyId === entry.id"
              :loading="busyId === entry.id"
              @click="saveEdit"
            >
              {{ $t('CONTACT_PANEL.LOGBOOK.SAVE') }}
            </NextButton>
          </div>
        </template>
        <p
          v-else
          class="text-sm text-n-slate-12 m-0 break-words leading-relaxed"
        >
          {{ entry.content }}
        </p>
      </div>
    </div>

    <div class="flex flex-col gap-2 mt-1">
      <textarea
        v-model="newEntryContent"
        :placeholder="$t('CONTACT_PANEL.LOGBOOK.PLACEHOLDER')"
        class="w-full p-2 text-sm rounded-lg border border-n-slate-4 bg-n-alpha-3 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand outline-none transition-all resize-none min-h-[60px]"
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

    <woot-delete-modal
      v-if="showDeleteModal"
      :show="showDeleteModal"
      :on-close="closeDeleteConfirm"
      :on-confirm="confirmDelete"
      :title="$t('CONTACT_PANEL.LOGBOOK.DELETE_CONFIRM.TITLE')"
      :message="$t('CONTACT_PANEL.LOGBOOK.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="$t('CONTACT_PANEL.LOGBOOK.DELETE_CONFIRM.YES')"
      :reject-text="$t('CONTACT_PANEL.LOGBOOK.DELETE_CONFIRM.NO')"
    />
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
