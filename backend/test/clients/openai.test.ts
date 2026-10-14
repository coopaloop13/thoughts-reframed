import { HttpResponse, http } from 'msw';
import { describe, expect, it, vi } from 'vitest';
import { createOpenAILLM, createReframer } from '../../src/clients/openai.js';
import { REFRAME_SYSTEM_PROMPT } from '../../src/pipeline/reframe-prompt.js';
import { msw } from '../setup.js';

const url = 'https://api.openai.com/v1/chat/completions';
const reframe = createReframer({ apiKey: 'OK', model: 'gpt-test' });

describe('reframer', () => {
  it('sends system prompt + transcript and returns trimmed content', async () => {
    let body: any; let auth: string | null = null;
    msw.use(http.post(url, async ({ request }) => { body = await request.json(); auth = request.headers.get('authorization');
      return HttpResponse.json({ choices: [{ message: { content: '  I am capable of learning from mistakes.  ' } }] }); }));
    expect(await reframe('I always mess things up')).toBe('I am capable of learning from mistakes.');
    expect(auth).toBe('Bearer OK');
    expect(body.model).toBe('gpt-test');
    expect(body.temperature).toBeUndefined();
    expect(body.messages[0]).toEqual({ role: 'system', content: REFRAME_SYSTEM_PROMPT });
    expect(body.messages[1]).toEqual({ role: 'user', content: 'I always mess things up' });
  });
  it('throws on non-2xx', async () => {
    msw.use(http.post(url, () => new HttpResponse('rate limited', { status: 429 })));
    await expect(reframe('x')).rejects.toThrow('OpenAI: 429');
  });
  it('throws on empty content', async () => {
    msw.use(http.post(url, () => HttpResponse.json({ choices: [{ message: { content: '' } }] })));
    await expect(reframe('x')).rejects.toThrow('OpenAI: empty reframe');
  });
  it('passes a timeout signal to fetch', async () => {
    msw.use(http.post(url, () => HttpResponse.json({ choices: [{ message: { content: 'ok' } }] })));
    const spy = vi.spyOn(globalThis, 'fetch');
    try {
      await reframe('x');
      expect(spy.mock.calls[0]?.[1]?.signal).toBeInstanceOf(AbortSignal);
    } finally { spy.mockRestore(); }
  });
});

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
