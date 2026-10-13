import { setupServer } from 'msw/node';
import { afterAll, afterEach, beforeAll } from 'vitest';
export const msw = setupServer();
beforeAll(() => msw.listen({ onUnhandledRequest: 'error' }));
afterEach(() => msw.resetHandlers());
afterAll(() => msw.close());
