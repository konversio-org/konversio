import { mount, shallowMount } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import AuditLogFilters from '../AuditLogFilters.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountComponent = (props = {}, mountFn = shallowMount) =>
  mountFn(AuditLogFilters, {
    props,
    global: {
      directives: { 'on-click-outside': {} },
    },
  });

const openMenu = async (wrapper, index) => {
  await wrapper.findAllComponents(Button).at(index).trigger('click');
  return wrapper.findComponent(DropdownMenu);
};

describe('AuditLogFilters', () => {
  it('labels each menu with the active option', () => {
    const labels = mountComponent({ type: 'Inbox', sort: 'asc' }, mount)
      .findAllComponents(Button)
      .map(button => button.text());

    expect(labels).toEqual([
      'AUDIT_LOGS.FILTERS.EVENT_TYPES.INBOXES',
      'AUDIT_LOGS.FILTERS.SORT.OLDEST',
    ]);
  });

  it('falls back to all events and newest first', () => {
    const labels = mountComponent({}, mount)
      .findAllComponents(Button)
      .map(button => button.text());

    expect(labels).toEqual([
      'AUDIT_LOGS.FILTERS.ALL_EVENTS',
      'AUDIT_LOGS.FILTERS.SORT.NEWEST',
    ]);
  });

  it('falls back to all events when the type is not recognised', () => {
    const wrapper = mountComponent({ type: 'Bogus' }, mount);

    expect(wrapper.findAllComponents(Button).at(0).text()).toBe(
      'AUDIT_LOGS.FILTERS.ALL_EVENTS'
    );
  });

  it('groups event types into sections', async () => {
    const wrapper = mountComponent();
    const menu = await openMenu(wrapper, 0);

    expect(menu.props('menuSections').map(section => section.title)).toEqual([
      undefined,
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.ACCESS',
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.AGENTS_TEAMS',
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.CONFIGURATION',
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.CONVERSATIONS',
    ]);
  });

  it('emits a partial update when a filter action is picked', async () => {
    const wrapper = mountComponent({ type: 'Inbox' });
    const menu = await openMenu(wrapper, 0);
    menu.vm.$emit('action', { action: 'type', value: undefined });

    expect(wrapper.emitted('update')).toEqual([[{ type: undefined }]]);
  });

  it('emits a partial update for the sort menu', async () => {
    const wrapper = mountComponent();
    const menu = await openMenu(wrapper, 1);
    menu.vm.$emit('action', { action: 'sort', value: 'asc' });

    expect(wrapper.emitted('update')).toEqual([[{ sort: 'asc' }]]);
  });

  it('keeps a single menu open at a time', async () => {
    const wrapper = mountComponent();
    await openMenu(wrapper, 0);
    await openMenu(wrapper, 1);

    expect(wrapper.findAllComponents(DropdownMenu)).toHaveLength(1);
  });

  it('converts an applied range into start/end-of-day timestamps', () => {
    const wrapper = mountComponent();
    wrapper
      .findComponent(WootDatePicker)
      .vm.$emit('dateRangeChanged', [
        new Date(2026, 7, 3, 13, 4, 5),
        new Date(2026, 7, 12),
        'custom',
      ]);

    const [[payload]] = wrapper.emitted('update');
    expect(payload.range).toBe('custom');
    expect(new Date(payload.since * 1000)).toEqual(new Date(2026, 7, 3));
    expect(new Date(payload.until * 1000)).toEqual(
      new Date(2026, 7, 12, 23, 59, 59)
    );
  });
});
