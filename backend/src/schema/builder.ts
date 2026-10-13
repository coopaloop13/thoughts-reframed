import SchemaBuilder from '@pothos/core';
import type { Deps } from '../deps.js';

export type Context = { deps: Deps; userId: string | null };

export const builder = new SchemaBuilder<{
  Context: Context;
  Scalars: { DateTime: { Input: Date; Output: Date }; File: { Input: File; Output: never } };
}>({});

builder.scalarType('DateTime', {
  serialize: (d) => d.toISOString(),
  parseValue: (v) => { const d = new Date(String(v)); if (isNaN(+d)) throw new Error('Invalid DateTime'); return d; },
});
builder.scalarType('File', {
  serialize: () => { throw new Error('File is input-only'); },
  parseValue: (v) => { if (v instanceof File) return v; throw new Error('Expected a File upload'); },
});

builder.queryType({});
builder.mutationType({});
