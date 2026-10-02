import {
  usePlaygroundSession,
  KNOWLEDGE_TEXT_LIMIT,
} from './usePlaygroundSession';
import { useStore, useMapGetter } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

describe('usePlaygroundSession', () => {
  let dispatch;
  let assistant;
  const scenarios = [
    { id: 1, title: 'Alpha', enabled: true },
    { id: 2, title: 'Beta', enabled: true },
    { id: 3, title: 'Gamma', enabled: false },
  ];

  beforeEach(() => {
    assistant = {
      response_guidelines: ['Be nice'],
      guardrails: 'Never lie\nBe safe',
    };
    dispatch = vi.fn().mockResolvedValue();
    useStore.mockReturnValue({ dispatch });
    useMapGetter.mockImplementation(getter => {
      if (getter === 'pilot/assistants/getActiveId') return { value: 7 };
      if (getter === 'pilot/assistants/getActiveAssistant')
        return { value: assistant };
      if (getter === 'pilot/autopilot/getScenarios')
        return { value: scenarios };
      return { value: null };
    });
  });

  const setup = async () => {
    const session = usePlaygroundSession();
    await session.load(7);
    return session;
  };

  describe('load', () => {
    it('fetches scenarios and includes every enabled persisted scenario', async () => {
      const session = await setup();

      expect(dispatch).toHaveBeenCalledWith(
        'pilot/autopilot/fetchScenarios',
        7
      );
      expect(session.activeScenarios.value.map(s => s.id)).toEqual([1, 2]);
      expect(session.includedScenarioIds.value).toEqual([1, 2]);
    });

    it('parses persisted rules from arrays and newline-separated strings', async () => {
      const session = await setup();

      expect(session.guidelines.value).toEqual([
        { value: 'Be nice', included: true, persisted: true },
      ]);
      expect(session.guardrails.value).toEqual([
        { value: 'Never lie', included: true, persisted: true },
        { value: 'Be safe', included: true, persisted: true },
      ]);
    });
  });

  describe('playgroundConfig', () => {
    it('is null when nothing is overridden', async () => {
      const session = await setup();

      expect(session.playgroundConfig.value).toBeNull();
    });

    it('sends a scenario selection when persisted scenarios are excluded', async () => {
      const session = await setup();
      session.toggleScenario(2, false);

      expect(session.playgroundConfig.value).toEqual({ scenario_ids: [1] });
    });

    it('includes temporary scenarios with generated client identifiers', async () => {
      const session = await setup();
      session.addTemporaryScenario();
      const draft = session.temporaryScenarios.value[0];
      draft.title = ' Refund flow ';
      draft.description = 'Handles refunds';
      draft.instruction = 'Walk them through it.';

      expect(draft.clientId).toMatch(/^draft-/);
      expect(session.isTemporaryValid.value).toBe(true);
      expect(session.playgroundConfig.value.temporary_scenarios).toEqual([
        {
          client_id: draft.clientId,
          title: 'Refund flow',
          description: 'Handles refunds',
          instruction: 'Walk them through it.',
        },
      ]);
    });

    it('sends a replacement rule list when a persisted rule is excluded', async () => {
      const session = await setup();
      session.guidelines.value[0].included = false;

      expect(session.playgroundConfig.value.response_guidelines).toEqual([]);
    });

    it('sends a replacement rule list when a temporary rule is added', async () => {
      const session = await setup();
      session.addGuideline('Be brief');

      expect(session.playgroundConfig.value.response_guidelines).toEqual([
        'Be nice',
        'Be brief',
      ]);
    });

    it('includes knowledge text only when it is flagged in and non-blank', async () => {
      const session = await setup();
      session.knowledge.included = true;
      session.knowledge.text = '   ';

      expect(session.playgroundConfig.value).toBeNull();

      session.knowledge.text = 'Refunds take 30 days.';
      expect(session.playgroundConfig.value.knowledge_text).toEqual(
        'Refunds take 30 days.'
      );
    });
  });

  describe('validation', () => {
    it('flags incomplete temporary scenarios', async () => {
      const session = await setup();
      session.addTemporaryScenario();

      expect(session.isTemporaryValid.value).toBe(false);
      expect(session.temporaryErrors.value[0]).toEqual({
        title: true,
        description: true,
        instruction: true,
      });
    });

    it('detects knowledge text over the cap', async () => {
      const session = await setup();
      session.knowledge.text = 'x'.repeat(KNOWLEDGE_TEXT_LIMIT + 1);

      expect(session.characterCount.value).toBe(KNOWLEDGE_TEXT_LIMIT + 1);
      expect(session.knowledgeExceedsLimit.value).toBe(true);
    });
  });
});
