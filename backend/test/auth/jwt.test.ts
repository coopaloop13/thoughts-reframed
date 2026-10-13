import { describe, expect, it } from 'vitest';
import { jwtSecretFrom, signUserToken, verifyUserToken } from '../../src/auth/jwt.js';

const secret = jwtSecretFrom('test-secret');

describe('user jwt', () => {
  it('round-trips the user id', async () => {
    const token = await signUserToken('user-1', secret);
    expect(await verifyUserToken(token, secret)).toBe('user-1');
  });
  it('returns null for a bad signature', async () => {
    const token = await signUserToken('user-1', secret);
    expect(await verifyUserToken(token, jwtSecretFrom('other'))).toBeNull();
  });
  it('returns null for garbage', async () => {
    expect(await verifyUserToken('nope', secret)).toBeNull();
  });
});
