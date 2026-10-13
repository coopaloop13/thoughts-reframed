import { setupServer } from 'msw/node';
import { afterAll, afterEach, beforeAll } from 'vitest';
export const msw = setupServer();
beforeAll(() => msw.listen({ onUnhandledRequest: (req, print) => { if (!new URL(req.url).hostname.startsWith('localhost')) print.error(); } }));
afterEach(() => msw.resetHandlers());
afterAll(() => msw.close());
