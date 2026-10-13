import { SignJWT, jwtVerify } from 'jose';

export const jwtSecretFrom = (s: string) => new TextEncoder().encode(s);

export function signUserToken(userId: string, secret: Uint8Array) {
  return new SignJWT({}).setProtectedHeader({ alg: 'HS256' }).setSubject(userId).setIssuedAt().setExpirationTime('90d').sign(secret);
}

export async function verifyUserToken(token: string, secret: Uint8Array): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, secret);
    return payload.sub ?? null;
  } catch {
    return null;
  }
}
