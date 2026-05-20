import { frontendURL } from '../../../helper/URLHelper';
import PilotPlaceholder from './PilotPlaceholder.vue';
import PilotCopilotEntry from './PilotCopilotEntry.vue';
import PilotDocumentsPage from './documents/PilotDocumentsPage.vue';
import PilotFaqsPage from '../../../components-next/pilot/faqs/PilotFaqsPage.vue';

const commonMeta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

const section = (path, name, labelKey) => ({
  path: frontendURL(`accounts/:accountId/pilot/${path}`),
  name,
  component: PilotPlaceholder,
  meta: { ...commonMeta, pilotSection: labelKey },
});

export const routes = [
  {
    path: frontendURL('accounts/:accountId/pilot/faqs'),
    name: 'pilot_faqs',
    component: PilotFaqsPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_RESPONSES' },
  },
  {
    path: frontendURL('accounts/:accountId/pilot/documents'),
    name: 'pilot_documents',
    component: PilotDocumentsPage,
    meta: { ...commonMeta, pilotSection: 'SIDEBAR.PILOT_DOCUMENTS' },
  },
  section('scenarios', 'pilot_scenarios', 'SIDEBAR.PILOT_SCENARIOS'),
  section('playground', 'pilot_playground', 'SIDEBAR.PILOT_PLAYGROUND'),
  section('inboxes', 'pilot_inboxes', 'SIDEBAR.PILOT_INBOXES'),
  section('tools', 'pilot_tools', 'SIDEBAR.PILOT_TOOLS'),
  section('settings', 'pilot_settings_index', 'SIDEBAR.PILOT_SETTINGS'),
  {
    path: frontendURL('accounts/:accountId/pilot/copilot'),
    name: 'pilot_copilot',
    component: PilotCopilotEntry,
    meta: commonMeta,
  },
];
