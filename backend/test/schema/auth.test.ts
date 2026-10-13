import { describe, expect, it } from 'vitest';
import { users } from '../../src/db/schema.js';
import { gql, makeTestDeps, signIn } from '../helpers/app.js';

describe('auth', () => {
  it('signInWithApple creates a user and returns a token that works for me', async () => {
    const { yoga, apple } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    expect(user.hasVoice).toBe(false);
    const me = await gql(yoga, { query: '{ me { id } }' }, token);
    expect(me.data.me.id).toBe(user.id);
  });
  it('signInWithApple is idempotent per apple sub', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const a = await signIn(yoga, apple, 'same');
    const b = await signIn(yoga, apple, 'same');
    expect(a.user.id).toBe(b.user.id);
    expect(await deps.db.select().from(users)).toHaveLength(1);
  });
  it('rejects a bad apple token and creates no user', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const bad = await apple.sign({ sub: 'x', aud: 'com.other' });
    const r = await gql(yoga, { query: 'mutation($t:String!){ signInWithApple(identityToken:$t){ token } }', variables: { t: bad } });
    expect(r.errors?.[0].extensions?.code).toBe('INVALID_APPLE_TOKEN');
    expect(await deps.db.select().from(users)).toHaveLength(0);
  });
  it('me without a token is UNAUTHENTICATED', async () => {
    const { yoga } = await makeTestDeps();
    const r = await gql(yoga, { query: '{ me { id } }' });
    expect(r.errors?.[0].extensions?.code).toBe('UNAUTHENTICATED');
  });
  it('me with a bad token is UNAUTHENTICATED', async () => {
    const { yoga } = await makeTestDeps();
    const r = await gql(yoga, { query: '{ me { id } }' }, 'garbage');
    expect(r.errors?.[0].extensions?.code).toBe('UNAUTHENTICATED');
  });
});
