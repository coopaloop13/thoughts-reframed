import { describe, expect, it, vi } from 'vitest';
import { eq } from 'drizzle-orm';
import { sessions, users } from '../../src/db/schema.js';
import { gql, makeTestDeps, signIn } from '../helpers/app.js';
import { gqlUpload } from '../helpers/upload.js';

const ENROLL = 'mutation($s:File!,$t:String!){ enrollVoice(sample:$s, referenceText:$t){ id hasVoice } }';
const sample = { field: 's', bytes: new Uint8Array([5, 5, 5]), name: 'voice.m4a', type: 'audio/mp4' };

describe('enrollVoice', () => {
  it('stores the sample in R2, creates a VoiceStudio profile, marks hasVoice', async () => {
    const { yoga, apple, deps, fakes } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    const r = await gqlUpload(yoga, { query: ENROLL, variables: { t: 'The quick brown fox' }, file: sample }, token);
    expect(r.errors).toBeUndefined();
    expect(r.data.enrollVoice.hasVoice).toBe(true);
    expect(fakes.r2.get(`voices/${user.id}.m4a`)).toEqual(sample.bytes);
    const [row] = await deps.db.select().from(users).where(eq(users.id, user.id));
    expect(row.voiceProfileId).toBe('vp1');
    expect(row.voiceSampleKey).toBe(`voices/${user.id}.m4a`);
    expect(fakes.voice.profiles.get('vp1')).toBe(user.id);
  });
  it('re-enrolling replaces the old profile', async () => {
    const { yoga, apple, fakes } = await makeTestDeps();
    const { token } = await signIn(yoga, apple);
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample }, token);
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'b' }, file: sample }, token);
    expect([...fakes.voice.profiles.keys()]).toEqual(['vp2']);
  });
  it('requires auth', async () => {
    const { yoga } = await makeTestDeps();
    const r = await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample });
    expect(r.errors?.[0].extensions?.code).toBe('UNAUTHENTICATED');
  });
  it('surfaces VoiceStudio failure and leaves user without a voice', async () => {
    const { yoga, apple, fakes } = await makeTestDeps();
    fakes.voice.fail = 'createProfile';
    const { token } = await signIn(yoga, apple);
    const r = await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample }, token);
    expect(r.errors?.[0].message).toBe('Unexpected error.');
    const me = await gql(yoga, { query: '{ me { hasVoice } }' }, token);
    expect(me.data.me.hasVoice).toBe(false);
    await gql(yoga, { query: 'mutation{ deleteAccount }' }, token);
    expect(fakes.r2.size).toBe(0);
  });
  it('keeps the new profile when deleting the old one fails', async () => {
    const { yoga, apple, deps, fakes } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample }, token);
    fakes.voice.fail = 'deleteProfile';
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const r = await gqlUpload(yoga, { query: ENROLL, variables: { t: 'b' }, file: sample }, token);
    spy.mockRestore();
    expect(r.errors).toBeUndefined();
    expect(r.data.enrollVoice.hasVoice).toBe(true);
    const [row] = await deps.db.select().from(users).where(eq(users.id, user.id));
    expect(row.voiceProfileId).toBe('vp2');
  });
});

describe('deleteAccount', () => {
  it('removes profile, R2 objects, and rows', async () => {
    const { yoga, apple, deps, fakes } = await makeTestDeps();
    const { token, user } = await signIn(yoga, apple);
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample }, token);
    await deps.db.insert(sessions).values({ userId: user.id, recordingKey: 'recordings/s1.m4a', audioKey: 'affirmations/s1.mp3' });
    fakes.r2.set('recordings/s1.m4a', new Uint8Array([1])); fakes.r2.set('affirmations/s1.mp3', new Uint8Array([2]));
    const r = await gql(yoga, { query: 'mutation{ deleteAccount }' }, token);
    expect(r.data.deleteAccount).toBe(true);
    expect(fakes.voice.profiles.size).toBe(0);
    expect(fakes.r2.size).toBe(0);
    expect(await deps.db.select().from(users)).toHaveLength(0);
    expect(await deps.db.select().from(sessions)).toHaveLength(0);
    const me = await gql(yoga, { query: '{ me { id } }' }, token);
    expect(me.errors?.[0].extensions?.code).toBe('UNAUTHENTICATED');
  });
  it('is retry-safe when R2 deletion fails', async () => {
    const { yoga, apple, deps, fakes } = await makeTestDeps();
    const { token } = await signIn(yoga, apple);
    await gqlUpload(yoga, { query: ENROLL, variables: { t: 'a' }, file: sample }, token);
    fakes.r2DeleteFail = true;
    const r1 = await gql(yoga, { query: 'mutation{ deleteAccount }' }, token);
    expect(r1.errors).toBeDefined();
    expect(await deps.db.select().from(users)).toHaveLength(1);
    expect(fakes.voice.profiles.size).toBe(1);
    fakes.r2DeleteFail = false;
    const r2 = await gql(yoga, { query: 'mutation{ deleteAccount }' }, token);
    expect(r2.data.deleteAccount).toBe(true);
    expect(fakes.voice.profiles.size).toBe(0);
    expect(fakes.r2.size).toBe(0);
    expect(await deps.db.select().from(users)).toHaveLength(0);
  });
});
