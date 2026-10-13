import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import { migrate } from 'drizzle-orm/pglite/migrator';
import * as schema from '../../src/db/schema.js';
import type { Db } from '../../src/db/client.js';

export async function makeTestDb(): Promise<Db> {
  const db = drizzle(new PGlite(), { schema });
  await migrate(db, { migrationsFolder: 'drizzle' });
  return db as unknown as Db; // same query builder at runtime; postgres-js type is the app-wide Db
}
