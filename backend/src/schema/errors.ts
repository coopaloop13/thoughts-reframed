import { GraphQLError } from 'graphql';
import type { Context } from './builder.js';

export type ErrorCode = 'UNAUTHENTICATED' | 'INVALID_APPLE_TOKEN' | 'VOICE_NOT_ENROLLED' | 'NOT_FOUND';
export const gqlError = (code: ErrorCode, message: string = code) => new GraphQLError(message, { extensions: { code } });
export function requireUser(ctx: Context): string {
  if (!ctx.userId) throw gqlError('UNAUTHENTICATED');
  return ctx.userId;
}
