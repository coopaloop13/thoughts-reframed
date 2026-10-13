import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema.js';

export function createDb(url: string) {
  return drizzle(postgres(url, { ssl: 'require', max: 5 }), { schema });
}
export type Db = ReturnType<typeof createDb>;
