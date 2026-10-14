import type { PubSub } from 'graphql-yoga';
import type { JWTVerifyGetKey } from 'jose';
import type { Agent } from './agent/agent.js';
import type { Db } from './db/client.js';
import type { SessionRow, TurnRow } from './db/schema.js';

export type R2 = {
  put(key: string, body: Uint8Array, contentType: string): Promise<void>;
  get(key: string): Promise<Uint8Array>;
  delete(key: string): Promise<void>;
  presignGet(key: string): Promise<string>;
};
export type VoiceStudio = {
  createProfile(a: { name: string; audio: Uint8Array; referenceText: string }): Promise<string>;
  deleteProfile(id: string): Promise<void>;
  transcribe(audio: Uint8Array): Promise<string>;
  synthesize(a: { text: string; voice: string }): Promise<Uint8Array>;
};
export type SessionPubSub = PubSub<{ session: [id: string, payload: SessionRow]; turn: [id: string, payload: TurnRow] }>;

export type Deps = {
  db: Db;
  pubsub: SessionPubSub;
  r2: R2;
  voice: VoiceStudio;
  agent: Agent;
  jwtSecret: Uint8Array;
  appleJwks: JWTVerifyGetKey;
  appleAudience: string;
  startPipeline: (sessionId: string) => void;
  startTurn: (turnId: string) => void;
};
