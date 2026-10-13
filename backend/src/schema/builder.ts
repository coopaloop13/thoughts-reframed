import SchemaBuilder from '@pothos/core';
import type { Deps } from '../deps.js';

export type Context = { deps: Deps; userId: string | null };

export const builder = new SchemaBuilder<{
  Context: Context;
  DefaultFieldNullability: false;
  Scalars: { DateTime: { Input: Date; Output: Date }; File: { Input: File; Output: never } };
}>({ defaultFieldNullability: false });

builder.scalarType('DateTime', {
  serialize: (d) => d.toISOString(),
  parseValue: (v) => { const d = new Date(String(v)); if (isNaN(+d)) throw new Error('Invalid DateTime'); return d; },
});
builder.scalarType('File', {
  serialize: () => { throw new Error('File is input-only'); },
  parseValue: (v) => { if (v && typeof (v as File).arrayBuffer === 'function') return v as File; /* Yoga's ponyfilled File is not instanceof global File */ throw new Error('Expected a File upload'); },
});

builder.queryType({});
builder.mutationType({});
builder.subscriptionType({});
