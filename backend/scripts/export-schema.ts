import { writeFileSync } from 'node:fs';
import { printSchema, lexicographicSortSchema } from 'graphql';
import { schema } from '../src/schema/index.js';
writeFileSync(new URL('../schema.graphql', import.meta.url), printSchema(lexicographicSortSchema(schema)) + '\n');
console.log('wrote schema.graphql');
