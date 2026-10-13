import { verifyAppleIdentityToken } from '../auth/apple.js';
import { signUserToken } from '../auth/jwt.js';
import { users, type UserRow } from '../db/schema.js';
import { builder } from './builder.js';
import { gqlError } from './errors.js';
import { UserType } from './user.js';

const AuthPayload = builder.objectRef<{ token: string; user: UserRow }>('AuthPayload').implement({
  fields: (t) => ({ token: t.exposeString('token'), user: t.field({ type: UserType, resolve: (p) => p.user }) }),
});

builder.mutationField('signInWithApple', (t) => t.field({
  type: AuthPayload,
  args: { identityToken: t.arg.string({ required: true }) },
  resolve: async (_r, { identityToken }, { deps }) => {
    const { sub } = await verifyAppleIdentityToken(identityToken, { jwks: deps.appleJwks, audience: deps.appleAudience })
      .catch(() => { throw gqlError('INVALID_APPLE_TOKEN'); });
    const [user] = await deps.db.insert(users).values({ appleSub: sub })
      .onConflictDoUpdate({ target: users.appleSub, set: { appleSub: sub } }).returning();
    return { token: await signUserToken(user.id, deps.jwtSecret), user };
  },
}));
