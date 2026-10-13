import { expect, it } from 'vitest';
import { schema } from '../../src/schema/index.js';

// printSchema trips vitest's graphql dual-module check, so assert on field types directly.
it('fields are non-null by default', () => {
  expect(String(schema.getQueryType()!.getFields().me.type)).toBe('User!');
  expect(String(schema.getSubscriptionType()!.getFields().sessionUpdated.type)).toBe('Session!');
  expect(String(schema.getQueryType()!.getFields().session.type)).toBe('Session');
});
