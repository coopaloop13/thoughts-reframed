import { Container, getContainer } from '@cloudflare/containers';

type Env = { BACKEND: DurableObjectNamespace<Backend> } & Record<
  'DATABASE_URL' | 'JWT_SECRET' | 'APPLE_BUNDLE_ID' | 'R2_ACCOUNT_ID' | 'R2_ACCESS_KEY_ID' | 'R2_SECRET_ACCESS_KEY' | 'R2_BUCKET' | 'VOICESTUDIO_URL' | 'VOICESTUDIO_API_KEY' | 'OPENAI_API_KEY' | 'OPENAI_MODEL',
  string
>;

export class Backend extends Container<Env> {
  defaultPort = 8080;
  sleepAfter = '10m';
  constructor(ctx: DurableObjectState<{}>, env: Env) {
    super(ctx, env);
    const { BACKEND: _, ...vars } = env;
    this.envVars = vars;
  }
}

export default {
  // ponytail: single container instance; shard by user id when one box is not enough.
  fetch: (request: Request, env: Env) => getContainer(env.BACKEND).fetch(request), // fetch, not containerFetch: WebSockets must pass through
} satisfies ExportedHandler<Env>;
