import {
  extractChangedAccountUserValues,
  generateTranslationPayload,
  generateLogActionKey,
  EVENT_TYPE_GROUPS,
  auditLogFiltersFromQuery,
  buildAuditLogRouteQuery,
} from '../auditlogHelper'; // import the functions

describe('Helper functions', () => {
  const agentList = [
    { id: 1, name: 'Agent 1' },
    { id: 2, name: 'Agent 2' },
    { id: 3, name: 'Agent 3' },
  ];

  describe('extractChangedAccountUserValues', () => {
    it('should correctly extract values when role is changed', () => {
      const changes = {
        role: [0, 1],
      };
      const { changes: extractedChanges, values } =
        extractChangedAccountUserValues(changes);
      expect(extractedChanges).toEqual(['role']);
      expect(values).toEqual(['administrator']);
    });

    it('should correctly extract values when availability is changed', () => {
      const changes = {
        availability: [0, 2],
      };
      const { changes: extractedChanges, values } =
        extractChangedAccountUserValues(changes);
      expect(extractedChanges).toEqual(['availability']);
      expect(values).toEqual(['busy']);
    });

    it('should correctly extract values when both are changed', () => {
      const changes = {
        role: [1, 0],
        availability: [1, 2],
      };
      const { changes: extractedChanges, values } =
        extractChangedAccountUserValues(changes);
      expect(extractedChanges).toEqual(['role', 'availability']);
      expect(values).toEqual(['agent', 'busy']);
    });
  });

  describe('generateTranslationPayload', () => {
    it('should handle AccountUser create', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'create',
        user_id: 1,
        auditable_id: 123,
        audited_changes: {
          user_id: 2,
          role: 1,
        },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 123,
        invitee: 'Agent 2',
        role: 'administrator',
      });
    });

    it('should handle AccountUser update', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable_id: 123,
        audited_changes: {
          user_id: 2,
          role: [1, 0],
          availability: [0, 2],
        },
        auditable: {
          user_id: 3,
        },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 123,
        user: 'Agent 3',
        attributes: ['role', 'availability'],
        values: ['agent', 'busy'],
      });
    });

    it('should handle InboxMember or TeamMember', () => {
      const auditLogItemInboxMember = {
        auditable_type: 'InboxMember',
        action: 'create',
        audited_changes: {
          user_id: 2,
        },
        user_id: 1,
        auditable_id: 789,
      };

      const payloadInboxMember = generateTranslationPayload(
        auditLogItemInboxMember,
        agentList
      );
      expect(payloadInboxMember).toEqual({
        agentName: 'Agent 1',
        id: 789,
        user: 'Agent 2',
      });

      const auditLogItemTeamMember = {
        auditable_type: 'TeamMember',
        action: 'create',
        audited_changes: {
          user_id: 3,
        },
        user_id: 1,
        auditable_id: 789,
      };

      const payloadTeamMember = generateTranslationPayload(
        auditLogItemTeamMember,
        agentList
      );
      expect(payloadTeamMember).toEqual({
        agentName: 'Agent 1',
        id: 789,
        user: 'Agent 3',
      });
    });

    it('should handle generic case like Team create', () => {
      const auditLogItem = {
        auditable_type: 'Team',
        action: 'create',
        user_id: 1,
        auditable_id: 456,
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 456,
      });
    });

    it('should interpolate the conversation display id for message deletions', () => {
      const auditLogItem = {
        auditable_type: 'Message',
        action: 'destroy',
        user_id: 1,
        auditable_id: 55123,
        audited_changes: { display_id: 1234 },
      };

      const payload = generateTranslationPayload(auditLogItem, agentList);
      expect(payload).toEqual({
        agentName: 'Agent 1',
        id: 55123,
        conversationId: 1234,
      });
    });
  });

  describe('generateLogActionKey', () => {
    it('should generate correct action key when user updates self', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable: {
          user_id: 1,
        },
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.ACCOUNT_USER.EDIT.SELF');
    });

    it('should generate correct action key when user updates other agent', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable: {
          user_id: 2,
        },
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.ACCOUNT_USER.EDIT.OTHER');
    });

    it('should generate correct action key when updating a deleted user', () => {
      const auditLogItem = {
        auditable_type: 'AccountUser',
        action: 'update',
        user_id: 1,
        auditable: null,
      };

      const logActionKey = generateLogActionKey(auditLogItem);
      expect(logActionKey).toEqual('AUDIT_LOGS.ACCOUNT_USER.EDIT.DELETED');
    });

    it('should generate the message deletion key', () => {
      const auditLogItem = {
        auditable_type: 'Message',
        action: 'destroy',
        user_id: 1,
        auditable_id: 42,
      };

      expect(generateLogActionKey(auditLogItem)).toEqual(
        'AUDIT_LOGS.MESSAGE.DELETE'
      );
    });
  });

  describe('EVENT_TYPE_GROUPS', () => {
    it('groups the supported event types by domain', () => {
      expect(EVENT_TYPE_GROUPS.map(group => group.key)).toEqual([
        'ACCESS',
        'AGENTS_TEAMS',
        'CONFIGURATION',
        'CONVERSATIONS',
      ]);
    });

    it('exposes every supported auditable type', () => {
      const values = EVENT_TYPE_GROUPS.flatMap(group =>
        group.types.map(type => type.value)
      );
      expect(values).toEqual([
        'User',
        'AccountUser',
        'Team',
        'TeamMember',
        'InboxMember',
        'Account',
        'Inbox',
        'Webhook',
        'AutomationRule',
        'Macro',
        'Conversation',
        'Message',
      ]);
    });
  });

  describe('auditLogFiltersFromQuery', () => {
    it('maps a route query to API filters', () => {
      expect(
        auditLogFiltersFromQuery({
          page: '2',
          q: 'jane',
          type: 'Inbox',
          sort: 'asc',
          since: '100',
          until: '200',
        })
      ).toEqual({
        page: 2,
        q: 'jane',
        types: ['Inbox'],
        sort: 'asc',
        since: 100,
        until: 200,
      });
    });

    it('defaults to page one and drops unsupported values', () => {
      expect(
        auditLogFiltersFromQuery({ sort: 'sideways', type: 'Bogus' })
      ).toEqual({ page: 1 });
    });

    it('ignores a half-open date window', () => {
      expect(auditLogFiltersFromQuery({ since: '100' })).toEqual({ page: 1 });
    });
  });

  describe('buildAuditLogRouteQuery', () => {
    it('drops undefined and empty values', () => {
      expect(
        buildAuditLogRouteQuery({
          q: '',
          type: 'Inbox',
          range: 'last7days',
          page: undefined,
        })
      ).toEqual({ type: 'Inbox', range: 'last7days' });
    });
  });
});
