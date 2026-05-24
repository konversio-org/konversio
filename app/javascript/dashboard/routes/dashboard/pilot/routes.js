import { frontendURL } from '../../../helper/URLHelper';
import PilotCopilotEntry from './PilotCopilotEntry.vue';
import PilotDocumentsPage from './documents/PilotDocumentsPage.vue';
import PilotFaqsPage from '../../../components-next/pilot/faqs/PilotFaqsPage.vue';
import ScenarioBuilder from './ScenarioBuilder.vue';
import PlaygroundPanel from './PlaygroundPanel.vue';
import PilotInboxesPage from './PilotInboxesPage.vue';
import PilotToolsPage from './tools/PilotToolsPage.vue';
import AutopilotIndex from './AutopilotIndex.vue';
import PilotActivityPage from './PilotActivityPage.vue';

const commonMeta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/pilot/faqs'),
    name: 'pilot_faqs',
    component: PilotFaqsPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_RESPONSES' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/faqs/pending'),
    name: 'pilot_faqs_pending',
    component: PilotFaqsPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_RESPONSES' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/documents'),
    name: 'pilot_documents',
    component: PilotDocumentsPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_DOCUMENTS' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/scenarios'),
    name: 'pilot_scenarios',
    component: ScenarioBuilder,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_SCENARIOS' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/playground'),
    name: 'pilot_playground',
    component: PlaygroundPanel,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_PLAYGROUND' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/inboxes'),
    name: 'pilot_inboxes',
    component: PilotInboxesPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_INBOXES' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/tools'),
    name: 'pilot_tools',
    component: PilotToolsPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_TOOLS' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/activity'),
    name: 'pilot_activity',
    component: PilotActivityPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_ACTIVITY' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/settings'),
    name: 'pilot_settings',
    component: AutopilotIndex,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_SETTINGS' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/copilot'),
    name: 'pilot_copilot',
    component: PilotCopilotEntry,
    meta: commonMeta,
  },
];
