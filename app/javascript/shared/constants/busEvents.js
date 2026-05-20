export const BUS_EVENTS = {
  SHOW_ALERT: 'SHOW_ALERT',
  START_NEW_CONVERSATION: 'START_NEW_CONVERSATION',
  FOCUS_CUSTOM_ATTRIBUTE: 'FOCUS_CUSTOM_ATTRIBUTE',
  SCROLL_TO_MESSAGE: 'SCROLL_TO_MESSAGE',
  MESSAGE_SENT: 'MESSAGE_SENT',
  ON_MESSAGE_LIST_SCROLL: 'ON_MESSAGE_LIST_SCROLL',
  WEBSOCKET_DISCONNECT: 'WEBSOCKET_DISCONNECT',
  WEBSOCKET_RECONNECT: 'WEBSOCKET_RECONNECT',
  WEBSOCKET_RECONNECT_COMPLETED: 'WEBSOCKET_RECONNECT_COMPLETED',
  TOGGLE_REPLY_TO_MESSAGE: 'TOGGLE_REPLY_TO_MESSAGE',
  SHOW_TOAST: 'newToastMessage',
  NEW_CONVERSATION_MODAL: 'newConversationModal',
  INSERT_INTO_RICH_EDITOR: 'insertIntoRichEditor',
  INSERT_INTO_NORMAL_EDITOR: 'insertIntoNormalEditor',
  // Pilot in-composer preview surface. PilotActionsMenu fires START
  // before the API call to render the thinking state immediately; then
  // READY or ERROR once the API resolves. ReplyBox owns the preview
  // state and swaps WootMessageEditor for PilotPreviewPanel while
  // active. CLOSE is fired by the panel itself (Accept or Dismiss).
  PILOT_PREVIEW_START: 'pilotPreviewStart',
  PILOT_PREVIEW_READY: 'pilotPreviewReady',
  PILOT_PREVIEW_ERROR: 'pilotPreviewError',
  PILOT_PREVIEW_CLOSE: 'pilotPreviewClose',
};
