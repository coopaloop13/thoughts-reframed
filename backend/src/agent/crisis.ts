// Keyword floor under the model's own judgement: a hit here is always a crisis, whatever the model says.
// Deliberately narrow so "this project is killing me" does not trip it.
export const CRISIS_PATTERN =
  /\b(suicid\w*|kill(ing)? myself|end (it all|my life)|want(ing)? to die|self[- ]?harm\w*|hurt(ing)? myself|cut(ting)? myself|better off without me|better off dead|no reason to (live|go on))\b/i;

export const hasCrisisLanguage = (text: string): boolean => CRISIS_PATTERN.test(text);
