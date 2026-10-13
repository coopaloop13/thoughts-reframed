import { builder } from './builder.js';
import { gqlError, requireUser } from './errors.js';
import { SessionType, loadOwnedSession } from './session.js';

const done = (r: { status: string }) => r.status === 'COMPLETED' || r.status === 'FAILED';

builder.subscriptionField('sessionUpdated', (t) => t.field({
  type: SessionType,
  args: { id: t.arg.id({ required: true }) },
  // Attach the listener before reading the row so no update falls in the gap; replay the snapshot first.
  subscribe: async function* (_r, { id }, ctx) {
    const userId = requireUser(ctx);
    const it = ctx.deps.pubsub.subscribe('session', String(id))[Symbol.asyncIterator]();
    const pending = it.next();
    pending.catch(() => {});
    try {
      const row = await loadOwnedSession(ctx, userId, String(id));
      if (!row) throw gqlError('NOT_FOUND', 'Session not found');
      yield row;
      if (done(row)) return;
      for (let r = await pending; !r.done; r = await it.next()) {
        yield r.value;
        if (done(r.value)) return;
      }
    } finally {
      await it.return?.();
    }
  },
  resolve: (payload) => payload,
}));
