<script>
import ConversationCard from './widgets/conversation/ConversationCard.vue';
import ConversationCardExpanded from 'dashboard/components-next/Conversation/ConversationCard/ConversationCardExpanded.vue';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import ConversationContextMenu from './widgets/conversation/contextMenu/Index.vue';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

export default {
  components: {
    ConversationCard,
    ConversationCardExpanded,
    ContextMenu,
    ConversationContextMenu,
  },
  inject: [
    'selectConversation',
    'deSelectConversation',
    'assignAgent',
    'assignTeam',
    'assignLabels',
    'removeLabels',
    'updateConversationStatus',
    'toggleContextMenu',
    'markAsUnread',
    'markAsRead',
    'assignPriority',
    'isConversationSelected',
    'deleteConversation',
  ],
  props: {
    source: {
      type: Object,
      required: true,
    },
    teamId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
    showAssignee: {
      type: Boolean,
      default: false,
    },
    showExpanded: {
      type: Boolean,
      default: false,
    },
    pilotAssistantId: {
      type: [String, Number],
      default: 0,
    },
  },
  data() {
    return {
      showContextMenu: false,
      contextMenu: { x: null, y: null },
    };
  },
  computed: {
    currentChat() {
      return this.$store.getters.getSelectedChat;
    },
    inboxesList() {
      return this.$store.getters['inboxes/getInboxes'];
    },
    activeInbox() {
      return this.$store.getters.getSelectedInbox;
    },
    accountId() {
      return this.$store.getters.getCurrentAccountId;
    },
    assignee() {
      return this.source.meta?.assignee || {};
    },
    senderId() {
      return this.source.meta?.sender?.id;
    },
    currentContact() {
      return this.senderId
        ? this.$store.getters['contacts/getContact'](this.senderId)
        : {};
    },
    inbox() {
      const inboxId = this.source.inbox_id;
      return inboxId ? this.$store.getters['inboxes/getInbox'](inboxId) : {};
    },
    showInboxName() {
      return !this.activeInbox && this.inboxesList.length > 1;
    },
    isInboxView() {
      return !!this.activeInbox;
    },
    isActiveChat() {
      return this.currentChat.id === this.source.id;
    },
    showAssigneeForExpandedCard() {
      return this.showExpanded || this.showAssignee;
    },
    conversationPath() {
      return frontendURL(
        conversationUrl({
          accountId: this.accountId,
          activeInbox: this.activeInbox,
          id: this.source.id,
          label: this.label,
          teamId: this.teamId,
          conversationType: this.conversationType,
          foldersId: this.foldersId,
          pilotAssistantId: this.pilotAssistantId,
        })
      );
    },
  },
  methods: {
    onCardClick(e) {
      const path = this.conversationPath;
      if (!path) return;

      if (e.metaKey || e.ctrlKey) {
        e.preventDefault();
        window.open(
          `${window.konversioConfig.hostURL}${path}`,
          '_blank',
          'noopener,noreferrer'
        );
        return;
      }

      if (this.isActiveChat) return;
      this.$router.push({ path });
    },
    onExpandedSelect(checked) {
      if (checked) {
        this.selectConversation(this.source.id, this.inbox.id);
      } else {
        this.deSelectConversation(this.source.id, this.inbox.id);
      }
    },
    openContextMenu(e) {
      e.preventDefault();
      this.toggleContextMenu(true);
      this.contextMenu = {
        x: e.pageX || e.clientX,
        y: e.pageY || e.clientY,
      };
      this.showContextMenu = true;
    },
    closeContextMenu() {
      this.toggleContextMenu(false);
      this.showContextMenu = false;
      this.contextMenu = { x: null, y: null };
    },
    onUpdateConversation(status, snoozedUntil) {
      this.closeContextMenu();
      this.updateConversationStatus(this.source.id, status, snoozedUntil);
    },
    onAssignAgent(agent) {
      this.assignAgent(agent, [this.source.id]);
      this.closeContextMenu();
    },
    onAssignLabel(label) {
      this.assignLabels([label.title], [this.source.id]);
    },
    onRemoveLabel(label) {
      this.removeLabels([label.title], [this.source.id]);
    },
    onAssignTeam(team) {
      this.assignTeam(team, this.source.id);
      this.closeContextMenu();
    },
    onMarkAsUnread() {
      this.markAsUnread(this.source.id);
      this.closeContextMenu();
    },
    onMarkAsRead() {
      this.markAsRead(this.source.id);
      this.closeContextMenu();
    },
    onAssignPriority(priority) {
      this.assignPriority(priority, this.source.id);
      this.closeContextMenu();
    },
    onDeleteConversation() {
      this.deleteConversation(this.source.id);
      this.closeContextMenu();
    },
  },
};
</script>

<template>
  <ConversationCardExpanded
    v-if="showExpanded"
    :chat="source"
    :current-contact="currentContact"
    :assignee="assignee"
    :inbox="inbox"
    :selected="isConversationSelected(source.id)"
    :is-active-chat="isActiveChat"
    :show-assignee="showAssigneeForExpandedCard"
    :show-inbox-name="showInboxName"
    :is-inbox-view="isInboxView"
    @select-conversation="onExpandedSelect"
    @de-select-conversation="onExpandedSelect"
    @click="onCardClick"
    @contextmenu="openContextMenu"
  />

  <ConversationCard
    v-else
    :active-label="label"
    :team-id="teamId"
    :folders-id="foldersId"
    :chat="source"
    :conversation-type="conversationType"
    :selected="isConversationSelected(source.id)"
    :show-assignee="showAssignee"
    :pilot-assistant-id="pilotAssistantId"
    enable-context-menu
    @select-conversation="selectConversation"
    @de-select-conversation="deSelectConversation"
    @assign-agent="assignAgent"
    @assign-team="assignTeam"
    @assign-label="assignLabels"
    @remove-label="removeLabels"
    @update-conversation-status="updateConversationStatus"
    @context-menu-toggle="toggleContextMenu"
    @mark-as-unread="markAsUnread"
    @mark-as-read="markAsRead"
    @assign-priority="assignPriority"
    @delete-conversation="deleteConversation"
  />

  <ContextMenu
    v-if="showContextMenu"
    :x="contextMenu.x"
    :y="contextMenu.y"
    @close="closeContextMenu"
  >
    <ConversationContextMenu
      :status="source.status"
      :inbox-id="inbox.id"
      :priority="source.priority"
      :chat-id="source.id"
      :has-unread-messages="source.unread_count > 0"
      :conversation-labels="source.labels"
      :conversation-url="conversationPath"
      @update-conversation="onUpdateConversation"
      @assign-agent="onAssignAgent"
      @assign-label="onAssignLabel"
      @remove-label="onRemoveLabel"
      @assign-team="onAssignTeam"
      @mark-as-unread="onMarkAsUnread"
      @mark-as-read="onMarkAsRead"
      @assign-priority="onAssignPriority"
      @delete-conversation="onDeleteConversation"
      @close="closeContextMenu"
    />
  </ContextMenu>
</template>
