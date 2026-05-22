import { MESSAGE_TYPE } from 'shared/constants/messages';
import {
  showBadgeOnFavicon,
  resetFavicon,
  initFaviconSwitcher,
} from './faviconHelper';

import { EVENT_TYPES } from 'dashboard/routes/dashboard/settings/profile/constants.js';
import GlobalStore from 'dashboard/store';
import AudioNotificationStore from './AudioNotificationStore';
import {
  isConversationAssignedToMe,
  isConversationUnassigned,
  isMessageFromCurrentUser,
} from './AudioMessageHelper';
import WindowVisibilityHelper from './WindowVisibilityHelper';
import { useAlert } from 'dashboard/composables';

const NOTIFICATION_TIME = 30000;
const ALERT_DURATION = 10000;
const ALERT_PATH_PREFIX = '/audio/dashboard/';
const DEFAULT_TONE = 'ding';
const DEFAULT_ALERT_TYPE = ['none'];

export class DashboardAudioNotificationHelper {
  constructor(store) {
    if (!store) {
      throw new Error('store is required');
    }
    this.store = new AudioNotificationStore(store);

    this.notificationConfig = {
      audioAlertType: DEFAULT_ALERT_TYPE,
      playAlertOnlyWhenHidden: true,
      alertIfUnreadConversationExist: false,
    };

    this.recurringNotificationTimer = null;

    this.audioConfig = {
      audio: null,
      tone: DEFAULT_TONE,
      hasSentSoundPermissionsRequest: false,
    };

    this.currentUser = null;
    this.faviconSwitcherInitialized = false;

    try {
      this.syncChannel = new BroadcastChannel('konversio_conversation_sync');
      this.syncChannel.onmessage = event => {
        if (event.data?.type === 'CONVERSATION_READ') {
          const { id, lastSeen } = event.data;
          store.commit('UPDATE_MESSAGE_UNREAD_COUNT', {
            id,
            lastSeen,
            unreadCount: 0,
          });
        } else if (event.data?.type === 'CONVERSATION_UNREAD') {
          const { id, lastSeen, unreadCount } = event.data;
          store.commit('UPDATE_MESSAGE_UNREAD_COUNT', {
            id,
            lastSeen,
            unreadCount,
          });
        }
      };
    } catch (e) {
      // Ignore channel creation failures in sandboxed/unsupported environments
    }
  }

  intializeAudio = () => {
    const resourceUrl = `${ALERT_PATH_PREFIX}${this.audioConfig.tone}.mp3`;
    this.audioConfig.audio = new Audio(resourceUrl);
    return this.audioConfig.audio.load();
  };

  playAudioAlert = async () => {
    try {
      await this.audioConfig.audio.play();
    } catch (error) {
      if (
        error.name === 'NotAllowedError' &&
        !this.hasSentSoundPermissionsRequest
      ) {
        this.hasSentSoundPermissionsRequest = true;
        useAlert(
          'PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.SOUND_PERMISSION_ERROR',
          { usei18n: true, duration: ALERT_DURATION }
        );
      }
    }
  };

  set = ({
    currentUser,
    alwaysPlayAudioAlert,
    alertIfUnreadConversationExist,
    audioAlertType = DEFAULT_ALERT_TYPE,
    audioAlertTone = DEFAULT_TONE,
  }) => {
    this.notificationConfig = {
      ...this.notificationConfig,
      audioAlertType: audioAlertType.split('+').filter(Boolean),
      playAlertOnlyWhenHidden: !alwaysPlayAudioAlert,
      alertIfUnreadConversationExist: alertIfUnreadConversationExist,
    };

    this.currentUser = currentUser;

    const previousAudioTone = this.audioConfig.tone;
    this.audioConfig = {
      ...this.audioConfig,
      tone: audioAlertTone,
    };

    if (previousAudioTone !== audioAlertTone) {
      this.intializeAudio();
    }

    if (!this.faviconSwitcherInitialized) {
      initFaviconSwitcher(() => !this.store.hasUnreadConversation());
      this.faviconSwitcherInitialized = true;
    }
    this.clearRecurringTimer();
    this.playAudioEvery30Seconds();

    if (!this.storeSubscription && this.store?.store?.subscribe) {
      this.storeSubscription = this.store.store.subscribe(mutation => {
        if (
          [
            'UPDATE_CONVERSATION',
            'ADD_CONVERSATION',
            'ADD_MESSAGE',
            'DELETE_CONVERSATION',
            'UPDATE_MESSAGE_UNREAD_COUNT',
            'SET_ALL_CONVERSATION',
            'RECEIVE_CHAT_LIST',
          ].includes(mutation.type)
        ) {
          if (this.store.hasUnreadConversation()) {
            showBadgeOnFavicon();
          } else {
            resetFavicon();
          }
        }
      });
    }
  };

  shouldPlayAlert = () => {
    if (this.notificationConfig.playAlertOnlyWhenHidden) {
      return !WindowVisibilityHelper.isWindowVisible();
    }
    return true;
  };

  executeRecurringNotification = () => {
    if (this.store.hasUnreadConversation() && this.shouldPlayAlert()) {
      this.playAudioAlert();
      showBadgeOnFavicon();
    }
    this.resetRecurringTimer();
  };

  clearRecurringTimer = () => {
    if (this.recurringNotificationTimer) {
      clearTimeout(this.recurringNotificationTimer);
    }
  };

  resetRecurringTimer = () => {
    this.clearRecurringTimer();
    this.recurringNotificationTimer = setTimeout(
      this.executeRecurringNotification,
      NOTIFICATION_TIME
    );
  };

  playAudioEvery30Seconds = () => {
    const { audioAlertType, alertIfUnreadConversationExist } =
      this.notificationConfig;

    //  Audio alert is disabled dismiss the timer
    if (audioAlertType.includes('none')) return;

    // If unread conversation flag is disabled, dismiss the timer
    if (!alertIfUnreadConversationExist) return;

    this.resetRecurringTimer();
  };

  shouldNotifyOnMessage = message => {
    const { audioAlertType } = this.notificationConfig;
    if (audioAlertType.includes('none')) return false;
    if (audioAlertType.includes('all')) return true;

    const assignedToMe = isConversationAssignedToMe(
      message,
      this.currentUser.id
    );
    const isUnassigned = isConversationUnassigned(message);

    const shouldPlayAudio = [];

    if (
      audioAlertType.includes(EVENT_TYPES.ASSIGNED) ||
      audioAlertType.includes('mine')
    ) {
      shouldPlayAudio.push(assignedToMe);
    }
    if (audioAlertType.includes(EVENT_TYPES.UNASSIGNED)) {
      shouldPlayAudio.push(isUnassigned);
    }
    if (audioAlertType.includes(EVENT_TYPES.NOTME)) {
      shouldPlayAudio.push(!isUnassigned && !assignedToMe);
    }

    return shouldPlayAudio.some(Boolean);
  };

  onAssigneeChanged = conversation => {
    // Triggered when ActionCable broadcasts `assignee.changed`. The
    // canonical "now you must notice this" moment for bot→human handoffs:
    // the customer-facing message that prompted the handoff is suppressed
    // by the `pending` filter in onNewMessage, so without this hook the
    // assigned agent would never get a favicon badge or audio cue.
    if (!this.currentUser) return;
    const assigneeId =
      conversation?.meta?.assignee?.id ?? conversation?.assignee_id;
    if (assigneeId !== this.currentUser.id) return;

    // Show favicon badge when the agent's tab is backgrounded
    if (!WindowVisibilityHelper.isWindowVisible()) {
      showBadgeOnFavicon();
    }

    // Audio only when window is hidden or foreground alerts enabled
    if (!this.shouldPlayAlert()) return;

    const { audioAlertType } = this.notificationConfig;
    const assignmentAlertsEnabled =
      audioAlertType.includes('all') ||
      audioAlertType.includes(EVENT_TYPES.ASSIGNED) ||
      audioAlertType.includes('mine');
    if (assignmentAlertsEnabled) {
      this.playAudioAlert();
    }
  };

  onNewMessage = message => {
    // If the user does not have the permission to view the conversation, then dismiss the alert
    // FIX ME: There shouldn't be a new message if the user has no access to the conversation.
    if (!this.store.hasConversationPermission(this.currentUser)) {
      return;
    }

    // If the conversation status is pending, then dismiss the alert
    // This case is common for all audio event types
    if (this.store.isMessageFromPendingConversation(message)) {
      return;
    }

    // If the message is sent by the current user then dismiss the alert
    if (isMessageFromCurrentUser(message, this.currentUser.id)) {
      return;
    }

    // If the message type is not incoming or private, then dismiss the alert
    const { message_type: messageType, private: isPrivate } = message;
    if (messageType !== MESSAGE_TYPE.INCOMING && !isPrivate) {
      return;
    }

    if (WindowVisibilityHelper.isWindowVisible()) {
      // If the user looking at the conversation, then dismiss the alert
      if (this.store.isMessageFromCurrentConversation(message)) {
        return;
      }
    }

    // Always show favicon badge for valid incoming messages
    showBadgeOnFavicon();

    // Audio alerts respect user preferences
    if (!this.shouldNotifyOnMessage(message)) {
      return;
    }

    if (
      WindowVisibilityHelper.isWindowVisible() &&
      this.notificationConfig.playAlertOnlyWhenHidden
    ) {
      return;
    }

    this.playAudioAlert();
    this.playAudioEvery30Seconds();
  };
}

export default new DashboardAudioNotificationHelper(GlobalStore);
