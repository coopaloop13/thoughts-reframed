import { builder } from './builder.js';
import { gqlError, requireUser } from './errors.js';
import { SessionType, loadOwnedSession } from './session.js';

builder.subscriptionField('sessionUpdated', (t) => t.field({
  type: SessionType,
  args: { id: t.arg.id({ required: true }) },
  subscribe: async (_r, { id }, ctx) => {
    const userId = requireUser(ctx);
    if (!(await loadOwnedSession(ctx, userId, String(id)))) throw gqlError('NOT_FOUND', 'Session not found');
    return ctx.deps.pubsub.subscribe('session', String(id));
  },
  resolve: (payload) => payload,
}));
