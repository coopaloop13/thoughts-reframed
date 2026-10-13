import { createClient } from 'graphql-ws';
import WebSocket from 'ws';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions } from '../src/db/schema.js';
import { startServer } from '../src/server.js';
import { makeTestDeps, signIn } from './helpers/app.js';

let t: Awaited<ReturnType<typeof makeTestDeps>>; let srv: Awaited<ReturnType<typeof startServer>>;
beforeAll(async () => { t = await makeTestDeps(); srv = await startServer(t.deps, 0); });
afterAll(() => srv.close());

describe('server', () => {
  it('serves GraphQL over HTTP', async () => {
    const res = await fetch(`http://localhost:${srv.port}/graphql`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ query: '{ __typename }' }) });
    expect(await res.json()).toEqual({ data: { __typename: 'Query' } });
  });
  it('serves subscriptions over graphql-transport-ws with connectionParams token', async () => {
    const { token, user } = await signIn(t.yoga, t.apple);
    const [row] = await t.deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'r' }).returning();
    const client = createClient({ url: `ws://localhost:${srv.port}/graphql`, webSocketImpl: WebSocket, connectionParams: { token } });
    const events: any[] = [];
    let onEvent: () => void = () => {};
    const second = new Promise<void>((resolve, reject) => {
      onEvent = () => { if (events.length === 2) resolve(); };
      client.subscribe({ query: `subscription { sessionUpdated(id:"${row.id}") { status } }` }, { next: (e) => { events.push(e); onEvent(); }, error: reject, complete: () => {} });
    });
    await expect.poll(() => events.length).toBe(1);
    const [u] = await t.deps.db.update(sessions).set({ status: 'TRANSCRIBING' }).where(eq(sessions.id, row.id)).returning();
    t.deps.pubsub.publish('session', row.id, u);
    await second;
    expect(events[0]).toEqual({ data: { sessionUpdated: { status: 'UPLOADED' } } });
    expect(events[1]).toEqual({ data: { sessionUpdated: { status: 'TRANSCRIBING' } } });
    await client.dispose();
  });
});
