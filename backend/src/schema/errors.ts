import { createGraphQLError } from 'graphql-yoga';
import type { Context } from './builder.js';

export type ErrorCode = 'UNAUTHENTICATED' | 'INVALID_APPLE_TOKEN' | 'VOICE_NOT_ENROLLED' | 'NOT_FOUND';
// createGraphQLError (not `new GraphQLError`) so Yoga's masking recognises it as an expected error.
export const gqlError = (code: ErrorCode, message: string = code) => createGraphQLError(message, { extensions: { code } });
export function requireUser(ctx: Context): string {
  if (!ctx.userId) throw gqlError('UNAUTHENTICATED');
  return ctx.userId;
}
