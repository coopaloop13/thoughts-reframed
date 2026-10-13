import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair } from 'jose';

export async function makeAppleSigner(audience = 'com.example.app') {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
  const jwks = createLocalJWKSet({ keys: [jwk] });
  const sign = (claims: { sub: string; aud?: string; exp?: string }) =>
    new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'k1' })
      .setIssuer('https://appleid.apple.com').setAudience(claims.aud ?? audience)
      .setSubject(claims.sub).setIssuedAt().setExpirationTime(claims.exp ?? '1h').sign(privateKey);
  return { jwks, audience, sign };
}
