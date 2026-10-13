import { describe, expect, it } from 'vitest';
import { verifyAppleIdentityToken } from '../../src/auth/apple.js';
import { makeAppleSigner } from '../helpers/apple.js';

describe('verifyAppleIdentityToken', () => {
  it('returns the sub for a valid token', async () => {
    const apple = await makeAppleSigner();
    const token = await apple.sign({ sub: 'apple-123' });
    expect(await verifyAppleIdentityToken(token, apple)).toEqual({ sub: 'apple-123' });
  });
  it('rejects wrong audience', async () => {
    const apple = await makeAppleSigner();
    const token = await apple.sign({ sub: 'x', aud: 'com.other' });
    await expect(verifyAppleIdentityToken(token, apple)).rejects.toThrow('INVALID_APPLE_TOKEN');
  });
  it('rejects expired token', async () => {
    const apple = await makeAppleSigner();
    const token = await apple.sign({ sub: 'x', exp: '-1h' });
    await expect(verifyAppleIdentityToken(token, apple)).rejects.toThrow('INVALID_APPLE_TOKEN');
  });
});
