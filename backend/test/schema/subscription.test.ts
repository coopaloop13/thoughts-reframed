import { describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions } from '../../src/db/schema.js';
import { makeTestDeps, signIn } from '../helpers/app.js';

const SUB = (id: string) => `subscription { sessionUpdated(id:"${id}") { id status reframedText } }`;

async function openSse(yoga: any, query: string, token: string) {
  const res = await yoga.fetch(new Request('http://test/graphql', {
    method: 'POST', headers: { 'content-type': 'application/json', accept: 'text/event-stream', authorization: `Bearer ${token}` },
    body: JSON.stringify({ query }),
  }));
  const reader = res.body!.getReader(); const dec = new TextDecoder();
  let buf = '';
  return {
    status: res.status,
    next: async () => {
      for (;;) {
        let i: number;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const block = buf.slice(0, i); buf = buf.slice(i + 2);
          if (/^event: complete$/m.test(block)) return null;
          const m = block.match(/^data: (.*)$/m);
          if (m) return JSON.parse(m[1]);
        }
        const { value, done } = await reader.read();
        if (done) return null;
        buf += dec.decode(value, { stream: true });
      }
    },
    close: () => reader.cancel(),
  };
}

const ev = (id: string, status: string, reframedText: string | null = null) => ({ data: { sessionUpdated: { id, status, reframedText } } });

async function setup() {
  const { yoga, apple, deps } = await makeTestDeps();
  const { token, user } = await signIn(yoga, apple);
  const [row] = await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r' }).returning();
  const update = async (set: Partial<typeof sessions.$inferInsert>) => {
    const [u] = await deps.db.update(sessions).set(set).where(eq(sessions.id, row.id)).returning();
    deps.pubsub.publish('session', row.id, u);
  };
  return { yoga, token, row, update };
}

describe('sessionUpdated', () => {
  it('sends the current row, then streams published updates', async () => {
    const { yoga, token, row, update } = await setup();
    const sse = await openSse(yoga, SUB(row.id), token);
    expect(sse.status).toBe(200);
    expect(await sse.next()).toEqual(ev(row.id, 'UPLOADED'));
    await update({ status: 'REFRAMING', reframedText: 'ok' });
    expect(await sse.next()).toEqual(ev(row.id, 'REFRAMING', 'ok'));
    await sse.close();
  });
  it('replays missed updates via the snapshot', async () => {
    const { yoga, token, row, update } = await setup();
    await update({ status: 'REFRAMING' });
    const sse = await openSse(yoga, SUB(row.id), token);
    expect(await sse.next()).toEqual(ev(row.id, 'REFRAMING'));
    await sse.close();
  });
  it('ends after a terminal status', async () => {
    const { yoga, token, row, update } = await setup();
    const sse = await openSse(yoga, SUB(row.id), token);
    expect(await sse.next()).toEqual(ev(row.id, 'UPLOADED'));
    await update({ status: 'COMPLETED', reframedText: 'done' });
    expect(await sse.next()).toEqual(ev(row.id, 'COMPLETED', 'done'));
    expect(await sse.next()).toBeNull();
  });
  it('errors NOT_FOUND for someone else’s session', async () => {
    const { yoga, apple, deps } = await makeTestDeps();
    const owner = await signIn(yoga, apple, 'owner');
    const [row] = await deps.db.insert(sessions).values({ userId: owner.user.id, recordingKey: 'r' }).returning();
    const other = await signIn(yoga, apple, 'other');
    const sse = await openSse(yoga, SUB(row.id), other.token);
    expect((await sse.next()).errors[0].extensions.code).toBe('NOT_FOUND');
  });
  it('errors UNAUTHENTICATED without a token', async () => {
    const { yoga } = await makeTestDeps();
    const sse = await openSse(yoga, SUB('00000000-0000-0000-0000-000000000000'), '');
    expect((await sse.next()).errors[0].extensions.code).toBe('UNAUTHENTICATED');
  });
});
