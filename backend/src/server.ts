import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { createPubSub } from 'graphql-yoga';
import { useServer } from 'graphql-ws/use/ws';
import { WebSocketServer } from 'ws';
import { contextFromToken, createApp } from './app.js';
import { appleJwks } from './auth/apple.js';
import { jwtSecretFrom } from './auth/jwt.js';
import { createAgent } from './agent/agent.js';
import { createOpenAILLM } from './clients/openai.js';
import { createR2 } from './clients/r2.js';
import { createVoiceStudio } from './clients/voicestudio.js';
import { createDb } from './db/client.js';
import type { Deps } from './deps.js';
import { loadEnv } from './env.js';
import { createPipelineStarter, sweepStuckSessions } from './pipeline/run.js';

export async function startServer(deps: Deps, port: number) {
  const yoga = createApp(deps);
  const http = createServer(yoga);
  const wss = new WebSocketServer({ server: http, path: yoga.graphqlEndpoint });
  useServer({
    execute: (args: any) => args.rootValue.execute(args),
    subscribe: (args: any) => args.rootValue.subscribe(args),
    onSubscribe: async (ctx, _id, payload) => {
      const { schema, execute, subscribe, parse, validate } = yoga.getEnveloped({ ...ctx, req: ctx.extra.request, socket: ctx.extra.socket, params: payload });
      const token = (ctx.connectionParams as { token?: string } | undefined)?.token;
      const args = {
        schema, operationName: payload.operationName, document: parse(payload.query), variableValues: payload.variables,
        contextValue: await contextFromToken(deps, token), // yoga's own context factory reads request.headers (absent over WS)
        rootValue: { execute, subscribe },
      };
      const errors = validate(args.schema, args.document);
      return errors.length ? errors : args;
    },
  }, wss);
  await new Promise<void>((r) => http.listen(port, r));
  const addr = http.address();
  return {
    port: typeof addr === 'object' && addr ? addr.port : port,
    close: () => new Promise<void>((r) => { wss.close(); http.close(() => r()); }),
  };
}

export function depsFromEnv() {
  const env = loadEnv();
  const base = {
    db: createDb(env.DATABASE_URL),
    pubsub: createPubSub(),
    r2: createR2({ accountId: env.R2_ACCOUNT_ID, accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY, bucket: env.R2_BUCKET }),
    voice: createVoiceStudio({ baseUrl: env.VOICESTUDIO_URL, apiKey: env.VOICESTUDIO_API_KEY }),
    agent: createAgent(createOpenAILLM({ apiKey: env.OPENAI_API_KEY, model: env.OPENAI_MODEL })),
    jwtSecret: jwtSecretFrom(env.JWT_SECRET),
    appleJwks: appleJwks(),
    appleAudience: env.APPLE_BUNDLE_ID,
  };
  const deps = { ...base, startPipeline: () => {} } as Deps;
  deps.startPipeline = createPipelineStarter(deps);
  return { deps, env };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { deps, env } = depsFromEnv();
  const { port } = await startServer(deps, env.PORT);
  console.log(`listening on :${port}`);
  sweepStuckSessions(deps).then((ids) => ids.length && console.log('resumed sessions', ids)).catch((e) => console.error('sweep failed', e));
  setInterval(() => sweepStuckSessions(deps).catch((e) => console.error('sweep failed', e)), 120_000).unref();
}
