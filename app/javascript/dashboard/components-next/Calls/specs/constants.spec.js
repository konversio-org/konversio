import { CALL_KIND, getCallKind } from '../constants';

describe('getCallKind', () => {
  const call = (status, direction) => ({ status, direction });

  it('treats ringing and in-progress calls as ongoing', () => {
    expect(getCallKind(call('ringing', 'inbound'))).toBe(CALL_KIND.ONGOING);
    expect(getCallKind(call('in-progress', 'outbound'))).toBe(
      CALL_KIND.ONGOING
    );
  });

  it('derives missed vs no-reply from direction for no-answer calls', () => {
    expect(getCallKind(call('no-answer', 'inbound'))).toBe(CALL_KIND.MISSED);
    expect(getCallKind(call('no-answer', 'outbound'))).toBe(CALL_KIND.NO_REPLY);
  });

  it('treats failed and rejected calls as failed', () => {
    expect(getCallKind(call('failed', 'inbound'))).toBe(CALL_KIND.FAILED);
    expect(getCallKind(call('rejected', 'outbound'))).toBe(CALL_KIND.FAILED);
  });

  it('derives incoming vs outgoing from direction for completed calls', () => {
    expect(getCallKind(call('completed', 'inbound'))).toBe(CALL_KIND.INCOMING);
    expect(getCallKind(call('completed', 'outbound'))).toBe(CALL_KIND.OUTGOING);
  });
});
