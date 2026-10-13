const KEYS = [
  'DATABASE_URL', 'JWT_SECRET', 'APPLE_BUNDLE_ID',
  'R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET',
  'VOICESTUDIO_URL', 'VOICESTUDIO_API_KEY', 'OPENAI_API_KEY', 'OPENAI_MODEL',
] as const;

export type Env = Record<(typeof KEYS)[number], string> & { PORT: number };

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const port = Number(source.PORT || 8080);
  if (!Number.isInteger(port) || port <= 0) throw new Error(`Invalid PORT: ${source.PORT}`);
  const out: Record<string, string | number> = { PORT: port };
  for (const k of KEYS) {
    if (!source[k]) throw new Error(`Missing env var: ${k}`);
    out[k] = source[k]!;
  }
  return out as Env;
}
