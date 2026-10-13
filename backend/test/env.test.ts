import { describe, expect, it } from 'vitest';
import { loadEnv } from '../src/env.js';

const full = {
  DATABASE_URL: 'postgres://x', JWT_SECRET: 's', APPLE_BUNDLE_ID: 'com.x',
  R2_ACCOUNT_ID: 'a', R2_ACCESS_KEY_ID: 'k', R2_SECRET_ACCESS_KEY: 'sk', R2_BUCKET: 'b',
  VOICESTUDIO_URL: 'https://v', VOICESTUDIO_API_KEY: 'vk', OPENAI_API_KEY: 'ok', OPENAI_MODEL: 'gpt-x',
};

describe('loadEnv', () => {
  it('returns all vars with PORT defaulting to 8080', () => {
    expect(loadEnv(full)).toEqual({ ...full, PORT: 8080 });
  });
  it('names the first missing var', () => {
    const { JWT_SECRET: _, ...missing } = full;
    expect(() => loadEnv(missing)).toThrow('Missing env var: JWT_SECRET');
  });
  it('overrides PORT', () => {
    expect(loadEnv({ ...full, PORT: '3000' }).PORT).toBe(3000);
  });
  it('treats empty PORT as unset', () => {
    expect(loadEnv({ ...full, PORT: '' }).PORT).toBe(8080);
  });
  it('rejects invalid PORT', () => {
    expect(() => loadEnv({ ...full, PORT: 'abc' })).toThrow('Invalid PORT: abc');
  });
});
