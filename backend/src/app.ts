import { createYoga } from 'graphql-yoga';
import { verifyUserToken } from './auth/jwt.js';
import type { Deps } from './deps.js';
import type { Context } from './schema/builder.js';
import { schema } from './schema/index.js';

export async function contextFromToken(deps: Deps, token: string | undefined): Promise<Context> {
  const userId = token ? await verifyUserToken(token, deps.jwtSecret) : null;
  return { deps, userId };
}

export function createApp(deps: Deps) {
  return createYoga<{}, Context>({
    schema,
    graphqlEndpoint: '/graphql',
    graphiql: { subscriptionsProtocol: 'WS' },
    context: ({ request }) => contextFromToken(deps, request.headers.get('authorization')?.replace(/^Bearer /i, '')),
  });
}
