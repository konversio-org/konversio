import { dispatchWindowEvent } from '../CustomEventHelper';

describe('dispatchWindowEvent', () => {
  it('dispatches correct event', () => {
    window.dispatchEvent = vi.fn();
    dispatchWindowEvent({ eventName: 'konversio:ready' });
    expect(dispatchEvent).toHaveBeenCalled();
  });
});
