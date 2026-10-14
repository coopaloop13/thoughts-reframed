export type LLMMessage = { role: 'user' | 'assistant'; content: string };
export type LLMRequest = { system: string; messages: LLMMessage[]; json?: boolean };
/** Provider seam: one chat completion in, text out. Adapters live in src/clients/. */
export type LLM = (req: LLMRequest) => Promise<string>;
