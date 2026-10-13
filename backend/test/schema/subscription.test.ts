import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions } from '../../src/db/schema.js';
import { gql, makeTestDeps, signIn } from '../helpers/app.js';

const SUB = (id: string) => `subscription { sessionUpdated(id:"${id}") { id status reframedText } }`;

async function openSse(yoga: any, query: string, token: string) {
  const res = await yoga.fetch(new Request('http://test/graphql', {
    method: 'POST', headers: { 'content-type': 'application/json', accept: 'text/event-stream', authorization: `Bearer ${token}` },
    body: JSON.stringify({ query }),
  }));
  const reader = res.body!.getReader(); const dec = new TextDecoder();
  return {
    status: res.status,
    next: async () => {
      let buf = '';
      for (;;) {
        const { value, done } = await reader.read();
        if (done) return null;
        buf += dec.decode(value);
        const m = buf.match(/^data: (.*)$/m);
        if (m) return JSON.parse(m[1]);
      }
    },
    close: () => reader.cancel(),
  };
}

describe('sessionUpdated', () => {
  it('streams published updates for an owned session', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    const [row] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r' }).returning();
    const sse = await openSse(yoga, SUB(row.id), token);
    expect(sse.status).toBe(200);
    const first = sse.next(); // Yoga subscribes lazily on first read, so start reading before publishing
    await new Promise((r) => setTimeout(r, 50));
    const [updated] = await deps.db.update(sessions).set({ status: 'REFRAMING', reframedText: 'ok' }).where(eq(sessions.id, row.id)).returning();
    deps.pubsub.publish('session', row.id, updated);
    expect(await first).toEqual({ data: { sessionUpdated: { id: row.id, status: 'REFRAMING', reframedText: 'ok' } } });
    await sse.close();
  });
  it('errors NOT_FOUND for someone else’s session', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const owner = await signIn(yoga, apple, 'owner');
    const [row] = await deps.db.insert(sessions).values({ userId: owner.user.id, recordingKey: 'r' }).returning();
    const other = await signIn(yoga, apple, 'other');
    const r = await gql(yoga, { query: SUB(row.id) }, other.token);
    expect(r.errors?.[0].extensions?.code).toBe('NOT_FOUND');
  });
  it('errors UNAUTHENTICATED without a token', async () => {
    const { yoga } = await makeTestDeps();
    const r = await gql(yoga, { query: SUB('00000000-0000-0000-0000-000000000000') });
    expect(r.errors?.[0].extensions?.code).toBe('UNAUTHENTICATED');
  });
});
