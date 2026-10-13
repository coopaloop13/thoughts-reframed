import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

export const appleJwks = (): JWTVerifyGetKey => createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export async function verifyAppleIdentityToken(token: string, opts: { jwks: JWTVerifyGetKey; audience: string }) {
  try {
    const { payload } = await jwtVerify(token, opts.jwks, { issuer: 'https://appleid.apple.com', audience: opts.audience });
    if (!payload.sub) throw new Error('no sub');
    return { sub: payload.sub };
  } catch {
    throw new Error('INVALID_APPLE_TOKEN');
  }
}
