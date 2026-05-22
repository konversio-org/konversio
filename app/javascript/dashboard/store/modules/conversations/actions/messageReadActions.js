import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import mutationTypes from '../../../mutation-types';

export default {
  markMessagesRead: async ({ commit }, data) => {
    try {
      const {
        data: { id, agent_last_seen_at: lastSeen },
      } = await ConversationApi.markMessageRead(data);
      setTimeout(() => {
        commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, { id, lastSeen });
        try {
          const channel = new BroadcastChannel('konversio_conversation_sync');
          channel.postMessage({ type: 'CONVERSATION_READ', id, lastSeen });
          channel.close();
        } catch (e) {
          // Ignore channel post failures in sandboxed/unsupported environments
        }
      }, 4000);
    } catch (error) {
      // Handle error
    }
  },

  markMessagesUnread: async ({ commit }, { id }) => {
    try {
      const {
        data: { agent_last_seen_at: lastSeen, unread_count: unreadCount },
      } = await ConversationApi.markMessagesUnread({ id });
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen,
        unreadCount,
      });
      try {
        const channel = new BroadcastChannel('konversio_conversation_sync');
        channel.postMessage({
          type: 'CONVERSATION_UNREAD',
          id,
          lastSeen,
          unreadCount,
        });
        channel.close();
      } catch (e) {
        // Ignore channel post failures in sandboxed/unsupported environments
      }
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};
