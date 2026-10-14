import type { LLM } from '../agent/llm.js';

export function createOpenAILLM(cfg: { apiKey: string; model: string }): LLM {
  return async ({ system, messages, json }) => {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      signal: AbortSignal.timeout(60_000),
      headers: { authorization: `Bearer ${cfg.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        model: cfg.model,
        messages: [{ role: 'system', content: system }, ...messages],
        ...(json ? { response_format: { type: 'json_object' } } : {}),
      }),
    });
    if (!res.ok) throw new Error(`OpenAI: ${res.status}`);
    const data = await res.json() as { choices?: { message?: { content?: string } }[] };
    const text = data.choices?.[0]?.message?.content?.trim();
    if (!text) throw new Error('OpenAI: empty response');
    return text;
  };
}
