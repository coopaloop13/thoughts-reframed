import { describe, expect, it } from 'vitest';
import { hasCrisisLanguage } from '../../src/agent/crisis.js';

describe('hasCrisisLanguage', () => {
  it.each([
    'I want to kill myself', 'sometimes I think about suicide', 'I just want to end it all',
    'I have been hurting myself again', 'everyone would be better off without me', 'I want to die',
  ])('flags %s', (t) => expect(hasCrisisLanguage(t)).toBe(true));
  it.each(['I always mess things up', 'this project is killing me', 'I could die of embarrassment'])
    ('does not flag %s', (t) => expect(hasCrisisLanguage(t)).toBe(false));
});
