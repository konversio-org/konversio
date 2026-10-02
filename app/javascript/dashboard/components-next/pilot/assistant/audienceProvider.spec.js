import { valuesToRowValues, rowValuesToValues } from './audienceProvider';

describe('audienceProvider value conversion', () => {
  describe('#valuesToRowValues', () => {
    it('returns the first scalar for plain text inputs', () => {
      expect(valuesToRowValues(['hello'], { inputType: 'plainText' })).toBe(
        'hello'
      );
      expect(valuesToRowValues([], { inputType: 'plainText' })).toBe('');
    });

    it('returns the stored array for multi inputs', () => {
      expect(valuesToRowValues(['vip'], { inputType: 'multiSelect' })).toEqual([
        'vip',
      ]);
    });

    it('maps stored values to option objects for select inputs', () => {
      const filter = {
        inputType: 'searchSelect',
        options: [{ id: 'NL', name: 'Netherlands' }],
      };
      expect(valuesToRowValues(['NL'], filter)).toEqual({
        id: 'NL',
        name: 'Netherlands',
      });
    });

    it('falls back to an id/name pair when the option is unknown', () => {
      const filter = { inputType: 'booleanSelect', options: [] };
      expect(valuesToRowValues([true], filter)).toEqual({
        id: true,
        name: true,
      });
    });
  });

  describe('#rowValuesToValues', () => {
    it('wraps scalars in an array', () => {
      expect(rowValuesToValues('hello')).toEqual(['hello']);
      expect(rowValuesToValues(42)).toEqual([42]);
    });

    it('returns an empty array for blank scalars', () => {
      expect(rowValuesToValues('')).toEqual([]);
      expect(rowValuesToValues(null)).toEqual([]);
    });

    it('unwraps option objects', () => {
      expect(rowValuesToValues({ id: 'NL', name: 'Netherlands' })).toEqual([
        'NL',
      ]);
    });

    it('keeps arrays and drops blanks', () => {
      expect(rowValuesToValues(['vip', ''])).toEqual(['vip']);
    });
  });
});
