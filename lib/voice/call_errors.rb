module Voice::CallErrors
  # Meta returns this provider code when a contact has not opted in to calls yet.
  NO_CALL_PERMISSION_CODE = 138_006

  class NoCallPermission < StandardError; end
  class CallFailed < StandardError; end
  class NotRinging < StandardError; end
  class AlreadyAccepted < StandardError; end
  class CallAlreadyEnded < StandardError; end
end
