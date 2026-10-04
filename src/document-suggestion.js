/** Authored-only projection of the ordinary AgentSuggestion atom. Review actions belong to hosts. */
const reviews = new Set(['draft', 'ready']);
const kinds = new Set(['note', 'action', 'match', 'journey', 'source', 'share']);

export function assertAgentSuggestion(review, kind, confidence, evidence, content) {
  if (!reviews.has(review) || !kinds.has(kind) ||
      !(confidence === null || (typeof confidence === 'number' &&
        Number.isFinite(confidence) && confidence >= 0 && confidence <= 1)) ||
      !Array.isArray(evidence) || evidence.length > 64 ||
      evidence.some(id => typeof id !== 'string' || id.length === 0 || id.length > 128 ||
        /[\u0000-\u001f\u007f]/u.test(id)) ||
      new Set(evidence).size !== evidence.length ||
      typeof content !== 'string' || content.length === 0 || content.length > 32_768 ||
      content !== content.trim() || content.includes('\r') || content.includes('\u0000')) {
    throw new TypeError('Invalid authored AgentSuggestion');
  }
  return { review, kind, confidence, evidence, content };
}

export function assertAgentSuggestionBlock(block) {
  const props = block?.props;
  if (!props || typeof props !== 'object' || Array.isArray(props) ||
      (Object.keys(props).length !== 3 && Object.keys(props).length !== 4) ||
      Object.keys(props).some(key => !['review', 'kind', 'confidence', 'evidence'].includes(key)) ||
      (Object.hasOwn(props, 'confidence') && props.confidence == null) ||
      !Array.isArray(block.content) || block.content.length !== 1 ||
      block.content[0]?.type !== 'text' ||
      Object.keys(block.content[0]).some(key => !['type', 'text'].includes(key))) {
    throw new TypeError('Invalid authored AgentSuggestion block');
  }
  return assertAgentSuggestion(props.review, props.kind, props.confidence ?? null,
    props.evidence, block.content[0].text);
}
