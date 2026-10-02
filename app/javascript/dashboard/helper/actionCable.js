import AuthAPI from '../api/auth';
import BaseActionCableConnector from '../../shared/helpers/BaseActionCableConnector';
import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { useImpersonation } from 'dashboard/composables/useImpersonation';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const { isImpersonating } = useImpersonation();
const UNREAD_COUNTS_REFETCH_THROTTLE_MS = 5000;
const FILTERED_UNREAD_COUNTS_REFRESH_RETRY_MS = 30000;
const FILTERED_UNREAD_COUNTS_REFRESH_RETRY_JITTER_MS = 15000;
const MENTION_UNREAD_COUNTS_REFETCH_DELAY_MS =
  UNREAD_COUNTS_REFETCH_THROTTLE_MS;
const getFilteredUnreadCountsRefreshRetryDelay = () =>
  FILTERED_UNREAD_COUNTS_REFRESH_RETRY_MS +
  Math.random() * FILTERED_UNREAD_COUNTS_REFRESH_RETRY_JITTER_MS;

class ActionCableConnector extends BaseActionCableConnector {
  constructor(app, pubsubToken) {
    const { websocketURL = '' } = window.konversioConfig || {};
    super(app, pubsubToken, websocketURL);
    this.CancelTyping = [];
    this.lastUnreadCountsFetchAt = null;
    this.unreadCountsFetchTimer = null;
    this.mentionUnreadCountsFetchTimer = null;
    this.mentionUnreadCountsRetryTimer = null;
    this.filteredUnreadCountsRetryTimer = null;
    this.events = {
      'message.created': this.onMessageCreated,
      'message.updated': this.onMessageUpdated,
      'conversation.created': this.onConversationCreated,
      'conversation.status_changed': this.onStatusChange,
      'user:logout': this.onLogout,
      'page:reload': this.onReload,
      'assignee.changed': this.onAssigneeChanged,
      'conversation.typing_on': this.onTypingOn,
      'conversation.typing_off': this.onTypingOff,
      'conversation.contact_changed': this.onConversationContactChange,
      'presence.update': this.onPresenceUpdate,
      'contact.deleted': this.onContactDelete,
      'contact.updated': this.onContactUpdate,
      'conversation.mentioned': this.onConversationMentioned,
      'notification.created': this.onNotificationCreated,
      'notification.deleted': this.onNotificationDeleted,
      'notification.updated': this.onNotificationUpdated,
      'conversation.read': this.onConversationRead,
      'conversation.updated': this.onConversationUpdated,
      'conversation.unread_count_changed':
        this.onConversationUnreadCountChanged,
      'account.cache_invalidated': this.onCacheInvalidate,
      'copilot.message.created': this.onCopilotMessageCreated,
    };
  }

  // eslint-disable-next-line class-methods-use-this
  onReconnect = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
  };

  // eslint-disable-next-line class-methods-use-this
  onDisconnected = () => {
    emitter.emit(BUS_EVENTS.WEBSOCKET_DISCONNECT);
  };

  isAValidEvent = data => {
    return this.app.$store.getters.getCurrentAccountId === data.account_id;
  };

  onMessageUpdated = data => {
    this.app.$store.dispatch('updateMessage', data);
  };

  onPresenceUpdate = data => {
    if (isImpersonating.value) return;
    this.app.$store.dispatch('contacts/updatePresence', data.contacts);
    this.app.$store.dispatch('agents/updatePresence', data.users);
    this.app.$store.dispatch('setCurrentUserAvailability', data.users);
  };

  onConversationContactChange = payload => {
    const { meta = {}, id: conversationId } = payload;
    const { sender } = meta || {};
    if (conversationId) {
      this.app.$store.dispatch('updateConversationContact', {
        conversationId,
        ...sender,
      });
    }
  };

  onAssigneeChanged = payload => {
    const { id } = payload;
    if (id) {
      this.app.$store.dispatch('updateConversation', payload);
    }
    this.fetchConversationStats();
    DashboardAudioNotificationHelper.onAssigneeChanged(payload);
  };

  onConversationCreated = data => {
    this.app.$store.dispatch('addConversation', data);
    this.fetchConversationStats();
  };

  onConversationRead = data => {
    this.app.$store.dispatch('updateConversation', data);
  };

  // eslint-disable-next-line class-methods-use-this
  onLogout = () => AuthAPI.logout();

  onMessageCreated = data => {
    const {
      conversation: { last_activity_at: lastActivityAt },
      conversation_id: conversationId,
    } = data;
    DashboardAudioNotificationHelper.onNewMessage(data);
    this.app.$store.dispatch('addMessage', data);
    this.app.$store.dispatch('updateConversationLastActivity', {
      lastActivityAt,
      conversationId,
    });
  };

  // eslint-disable-next-line class-methods-use-this
  onReload = () => window.location.reload();

  onStatusChange = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onConversationUpdated = data => {
    this.app.$store.dispatch('updateConversation', data);
    this.fetchConversationStats();
  };

  onConversationUnreadCountChanged = () => {
    this.refreshConversationUnreadCountsWithFilteredRetry();
  };

  refreshConversationUnreadCountsWithFilteredRetry = () => {
    this.throttledFetchConversationUnreadCounts();
    this.scheduleFilteredUnreadCountsRetry();
  };

  throttledFetchConversationUnreadCounts = () => {
    const now = Date.now();
    const elapsedTime = now - this.lastUnreadCountsFetchAt;

    if (
      this.lastUnreadCountsFetchAt === null ||
      elapsedTime >= UNREAD_COUNTS_REFETCH_THROTTLE_MS
    ) {
      this.clearUnreadCountsFetchTimer();
      this.fetchConversationUnreadCounts();
      return;
    }

    if (this.unreadCountsFetchTimer) return;

    this.unreadCountsFetchTimer = setTimeout(() => {
      this.unreadCountsFetchTimer = null;
      this.fetchConversationUnreadCounts();
    }, UNREAD_COUNTS_REFETCH_THROTTLE_MS - elapsedTime);
  };

  clearUnreadCountsFetchTimer = () => {
    if (!this.unreadCountsFetchTimer) return;

    clearTimeout(this.unreadCountsFetchTimer);
    this.unreadCountsFetchTimer = null;
  };

  scheduleMentionUnreadCountsFetch = () => {
    if (!this.isFilteredUnreadCountsEnabled()) return;

    // Mention invalidation runs through the async dispatcher, and stale snapshots
    // can be served until the filtered-count backend refresh window opens.
    this.scheduleUnreadCountsFetchAfter(
      'mentionUnreadCountsFetchTimer',
      MENTION_UNREAD_COUNTS_REFETCH_DELAY_MS
    );
    this.scheduleUnreadCountsFetchAfter(
      'mentionUnreadCountsRetryTimer',
      getFilteredUnreadCountsRefreshRetryDelay(),
      { reset: true }
    );
  };

  scheduleFilteredUnreadCountsRetry = () => {
    if (!this.isFilteredUnreadCountsEnabled()) return;

    // Filtered snapshots can intentionally stay stale until the backend
    // refresh window opens.
    this.scheduleUnreadCountsFetchAfter(
      'filteredUnreadCountsRetryTimer',
      getFilteredUnreadCountsRefreshRetryDelay(),
      { reset: true }
    );
  };

  scheduleUnreadCountsFetchAfter = (
    timerName,
    delay,
    { reset = false } = {}
  ) => {
    if (this[timerName]) {
      if (!reset) return;

      clearTimeout(this[timerName]);
    }

    this[timerName] = setTimeout(() => {
      this[timerName] = null;
      this.throttledFetchConversationUnreadCounts();
    }, delay);
  };

  fetchConversationUnreadCounts = () => {
    if (!this.isConversationUnreadCountsEnabled()) return;

    this.lastUnreadCountsFetchAt = Date.now();
    this.app.$store.dispatch('conversationUnreadCounts/get');
  };

  isConversationUnreadCountsEnabled = () => {
    const accountId = this.app.$store.getters.getCurrentAccountId;
    const isFeatureEnabled =
      this.app.$store.getters['accounts/isFeatureEnabledonAccount'];

    return isFeatureEnabled?.(
      accountId,
      FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
    );
  };

  isFilteredUnreadCountsEnabled = () => {
    const accountId = this.app.$store.getters.getCurrentAccountId;
    const isFeatureEnabled =
      this.app.$store.getters['accounts/isFeatureEnabledonAccount'];

    return (
      isFeatureEnabled?.(accountId, FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS) &&
      isFeatureEnabled?.(accountId, FEATURE_FLAGS.UNREAD_COUNT_FOR_FILTERS)
    );
  };

  onTypingOn = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/create', {
      conversationId,
      user,
    });
    this.initTimer({ conversation, user });
  };

  onTypingOff = ({ conversation, user }) => {
    const conversationId = conversation.id;

    this.clearTimer(conversationId);
    this.app.$store.dispatch('conversationTypingStatus/destroy', {
      conversationId,
      user,
    });
  };

  onConversationMentioned = data => {
    this.app.$store.dispatch('addMentions', data);
    this.scheduleMentionUnreadCountsFetch();
  };

  clearTimer = conversationId => {
    const timerEvent = this.CancelTyping[conversationId];

    if (timerEvent) {
      clearTimeout(timerEvent);
      this.CancelTyping[conversationId] = null;
    }
  };

  initTimer = ({ conversation, user }) => {
    const conversationId = conversation.id;
    // Turn off typing automatically after 30 seconds
    this.CancelTyping[conversationId] = setTimeout(() => {
      this.onTypingOff({ conversation, user });
    }, 30000);
  };

  // eslint-disable-next-line class-methods-use-this
  fetchConversationStats = () => {
    emitter.emit('fetch_conversation_stats');
  };

  onContactDelete = data => {
    this.app.$store.dispatch(
      'contacts/deleteContactThroughConversations',
      data.id
    );
    this.fetchConversationStats();
  };

  onContactUpdate = data => {
    this.app.$store.dispatch('contacts/updateContact', data);
  };

  onNotificationCreated = data => {
    this.app.$store.dispatch('notifications/addNotification', data);
  };

  onNotificationDeleted = data => {
    this.app.$store.dispatch('notifications/deleteNotification', data);
  };

  onNotificationUpdated = data => {
    this.app.$store.dispatch('notifications/updateNotification', data);
  };

  onCopilotMessageCreated = data => {
    this.app.$store.dispatch('copilotMessages/upsert', data);
  };

  onCacheInvalidate = data => {
    const keys = data.cache_keys;
    this.app.$store.dispatch('labels/revalidate', { newKey: keys.label });
    this.app.$store.dispatch('inboxes/revalidate', { newKey: keys.inbox });
    this.app.$store.dispatch('teams/revalidate', { newKey: keys.team });

    if (this.isFilteredUnreadCountsEnabled()) {
      // Inbox/team/label visibility changes can change the accessible set used
      // by filtered unread counts even when no conversation row changes.
      this.refreshConversationUnreadCountsWithFilteredRetry();
    }
  };
}

export default {
  init(store, pubsubToken) {
    return new ActionCableConnector({ $store: store }, pubsubToken);
  },
};
