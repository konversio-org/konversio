import Cookies from 'js-cookie';
import {
  computeHashForUserData,
  fnv1a128,
  getUserCookieName,
  getUserString,
  hasUserKeys,
  setCookieWithDomain,
} from '../cookieHelpers';

describe('#getUserCookieName', () => {
  it('returns correct cookie name', () => {
    global.$konversio = { websiteToken: '123456' };
    expect(getUserCookieName()).toBe('cw_user_123456');
  });
});

describe('#getUserString', () => {
  it('returns correct user string', () => {
    expect(
      getUserString({
        user: {
          name: 'Pranav',
          email: 'pranav@example.com',
          avatar_url: 'https://images.chatwoot.com/placeholder',
          identifier_hash: '12345',
        },
        identifier: '12345',
      })
    ).toBe(
      'avatar_urlhttps://images.chatwoot.com/placeholderemailpranav@example.comnamePranavidentifier_hash12345identifier12345'
    );

    expect(
      getUserString({
        user: {
          email: 'pranav@example.com',
          avatar_url: 'https://images.chatwoot.com/placeholder',
        },
      })
    ).toBe(
      'avatar_urlhttps://images.chatwoot.com/placeholderemailpranav@example.comnameidentifier_hashidentifier'
    );
  });
});

describe('#fnv1a128', () => {
  // Adapted from https://github.com/sindresorhus/fnv1a/blob/main/test.js
  it.each([
    ['', '6c62272e07bb014262b821756295c58d'],
    ['h', 'd228cb69681a8caf78912b704e4a80c7'],
    ['he', '08809533baab1be95aa0733055ac4756'],
    ['hel', 'a68d42edea8b5822836dbc796afba45e'],
    ['hell', '693c5663cb757277b806e966a3a30986'],
    ['hello', 'e3e1efd54283d94f7081314b599d31b3'],
    ['hello ', 'b25bb89a6b3c64bf6ef7a7b7446bffe1'],
    ['hello w', '2e209201894ff78d8abb5e8130e37d92'],
    ['hello wo', '43448b61f2659b29b48d48f727ec064f'],
    ['hello wor', 'bc7f6d8b8005ec5129d8c81e1f6bad0f'],
    ['hello worl', '0eeb3653ea49c7de7dbe3d10a97e58d1'],
    ['hello world', '6c155799fdc8eec4b91523808e7726b7'],
  ])('hashes %j to %s', (value, expectedHash) => {
    expect(fnv1a128(value)).toBe(expectedHash);
  });

  it('hashes long input', () => {
    const loremIpsumParagraph = [
      'Lorem ipsum dolor sit amet, consectetuer adipiscing elit.',
      'Aenean commodo ligula eget dolor.',
      'Aenean massa.',
      'Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.',
      'Donec quam felis, ultricies nec, pellentesque eu, pretium quis, sem.',
      'Nulla consequat massa quis enim.',
      'Donec pede justo, fringilla vel, aliquet nec, vulputate eget, arcu.',
      'In enim justo, rhoncus ut, imperdiet a, venenatis vitae, justo.',
      'Nullam dictum felis eu pede mollis pretium.',
    ].join(' ');
    const value = Array(3).fill(loremIpsumParagraph).join(' ');

    expect(fnv1a128(value)).toBe('4fedf302b27b5c4dbaf35bd87a91f589');
  });

  it('hashes multi-byte UTF-8 characters', () => {
    expect(fnv1a128('🦄🌈')).toBe('0a25841ae4659905b36cb0d359fad39f');
  });
});

describe('#computeHashForUserData', () => {
  it.each([
    [{ user: {} }, '4a6876a8b6c40e1acb8f5f3663bc9440'],
    [
      {
        identifier: '12345',
        user: {
          name: 'Pranav',
          email: 'pranav@example.com',
          avatar_url: 'https://images.chatwoot.com/placeholder',
          identifier_hash: '12345',
        },
      },
      'd3cca1b490dd33284af994c893261564',
    ],
    [
      { user: { email: 'pranav@example.com' } },
      '64293c562cc4cc1eee65a4878acd59fd',
    ],
  ])('hashes %j to %s', (value, expectedHash) => {
    expect(computeHashForUserData(value)).toBe(expectedHash);
  });

  it('is deterministic for identical input', () => {
    const input = { identifier: '1', user: { email: 'pranav@example.com' } };
    expect(computeHashForUserData(input)).toBe(computeHashForUserData(input));
  });
});

describe('#hasUserKeys', () => {
  it('checks whether the allowed list of keys are present', () => {
    expect(hasUserKeys({})).toBe(false);
    expect(hasUserKeys({ randomKey: 'randomValue' })).toBe(false);
    expect(hasUserKeys({ avatar_url: 'randomValue' })).toBe(true);
  });
});

// Mock the 'set' method of the 'Cookies' object

describe('setCookieWithDomain', () => {
  beforeEach(() => {
    vi.spyOn(Cookies, 'set');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should set a cookie with default parameters', () => {
    setCookieWithDomain('myCookie', 'cookieValue');

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 365,
      sameSite: 'Lax',
      domain: undefined,
    });
  });

  it('should set a cookie with custom expiration and sameSite attribute', () => {
    setCookieWithDomain('myCookie', 'cookieValue', {
      expires: 30,
    });

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 30,
      sameSite: 'Lax',
      domain: undefined,
    });
  });

  it('should set a cookie with a specific base domain', () => {
    setCookieWithDomain('myCookie', 'cookieValue', {
      baseDomain: 'example.com',
    });

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 365,
      sameSite: 'Lax',
      domain: 'example.com',
    });
  });

  it('should stringify the cookie value when setting the value', () => {
    setCookieWithDomain(
      'myCookie',
      { value: 'cookieValue' },
      {
        baseDomain: 'example.com',
      }
    );

    expect(Cookies.set).toHaveBeenCalledWith(
      'myCookie',
      JSON.stringify({ value: 'cookieValue' }),
      {
        expires: 365,
        sameSite: 'Lax',
        domain: 'example.com',
      }
    );
  });

  it('should set a cookie with custom expiration, sameSite attribute, and specific base domain', () => {
    setCookieWithDomain('myCookie', 'cookieValue', {
      expires: 7,
      baseDomain: 'example.com',
    });

    expect(Cookies.set).toHaveBeenCalledWith('myCookie', 'cookieValue', {
      expires: 7,
      sameSite: 'Lax',
      domain: 'example.com',
    });
  });
});
