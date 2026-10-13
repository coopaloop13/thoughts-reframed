import type { YogaServerInstance } from 'graphql-yoga';

export async function gqlUpload(
  yoga: YogaServerInstance<any, any>,
  body: { query: string; variables: Record<string, unknown>; file: { field: string; bytes: Uint8Array; name: string; type: string } },
  token?: string,
) {
  const form = new FormData();
  form.append('operations', JSON.stringify({ query: body.query, variables: { ...body.variables, [body.file.field]: null } }));
  form.append('map', JSON.stringify({ '0': [`variables.${body.file.field}`] }));
  form.append('0', new File([body.file.bytes], body.file.name, { type: body.file.type }));
  const res = await yoga.fetch(new Request('http://test/graphql', { method: 'POST', body: form, headers: token ? { authorization: `Bearer ${token}` } : {} }));
  return res.json() as Promise<{ data?: any; errors?: { message: string; extensions?: { code?: string } }[] }>;
}
