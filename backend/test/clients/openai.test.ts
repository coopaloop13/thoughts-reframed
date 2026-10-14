import { HttpResponse, http } from 'msw';
import { describe, expect, it, vi } from 'vitest';
import { createOpenAILLM } from '../../src/clients/openai.js';
import { msw } from '../setup.js';

const url = 'https://api.openai.com/v1/chat/completions';

describe('createOpenAILLM', () => {
  const llm = createOpenAILLM({ apiKey: 'OK', model: 'gpt-test' });
  it('sends system + messages and returns trimmed content', async () => {
    let body: any; let auth: string | null = null;
    msw.use(http.post(url, async ({ request }) => { body = await request.json(); auth = request.headers.get('authorization');
      return HttpResponse.json({ choices: [{ message: { content: '  hello  ' } }] }); }));
    expect(await llm({ system: 'SYS', messages: [{ role: 'user', content: 'hi' }] })).toBe('hello');
    expect(auth).toBe('Bearer OK');
    expect(body.model).toBe('gpt-test');
    expect(body.messages).toEqual([{ role: 'system', content: 'SYS' }, { role: 'user', content: 'hi' }]);
    expect(body.response_format).toBeUndefined();
  });
  it('requests JSON mode when json is true', async () => {
    let body: any;
    msw.use(http.post(url, async ({ request }) => { body = await request.json(); return HttpResponse.json({ choices: [{ message: { content: '{}' } }] }); }));
    await llm({ system: 'S', messages: [{ role: 'user', content: 'u' }], json: true });
    expect(body.response_format).toEqual({ type: 'json_object' });
  });
  it('throws on non-2xx and on empty content', async () => {
    msw.use(http.post(url, () => new HttpResponse('nope', { status: 500 })));
    await expect(llm({ system: 'S', messages: [] })).rejects.toThrow('OpenAI: 500');
    msw.use(http.post(url, () => HttpResponse.json({ choices: [{ message: { content: '' } }] })));
    await expect(llm({ system: 'S', messages: [] })).rejects.toThrow('OpenAI: empty response');
  });
});
