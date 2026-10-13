import { REFRAME_SYSTEM_PROMPT } from '../pipeline/reframe-prompt.js';

export function createReframer(cfg: { apiKey: string; model: string }) {
  return async (transcript: string): Promise<string> => {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { authorization: `Bearer ${cfg.apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model: cfg.model, temperature: 0.7, messages: [
        { role: 'system', content: REFRAME_SYSTEM_PROMPT },
        { role: 'user', content: transcript },
      ] }),
    });
    if (!res.ok) throw new Error(`OpenAI: ${res.status}`);
    const json = await res.json() as { choices?: { message?: { content?: string } }[] };
    const text = json.choices?.[0]?.message?.content?.trim();
    if (!text) throw new Error('OpenAI: empty reframe');
    return text;
  };
}
