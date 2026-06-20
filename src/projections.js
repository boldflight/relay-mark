export function projectManifest(document, diagnostics = []) {
  const manifest = {
    type: "relaymark.manifest",
    version: 1,
    actions: [],
    mentions: [],
    forms: [],
    sources: [],
    diagnostics
  };

  visitBlocks(document.blocks || [], (block) => {
    if (block.type === "relay.action_row") {
      manifest.actions.push({
        block_id: block.id,
        action: block.props.action,
        target: block.props.target,
        destination: block.props.destination,
        visibility: block.props.visibility,
        review: block.props.review,
        evidence_refs: block.evidence_refs || block.props.evidence || [],
        args: {
          ...(block.props.args || {}),
          title: toPlainText(block).trim()
        }
      });

      if (typeof block.props.target === "string" && block.props.target.startsWith("entity:")) {
        manifest.mentions.push({
          block_id: block.id,
          kind: "entity",
          id: block.props.target.slice("entity:".length),
          label: block.props.target
        });
      }
    }

    if (block.type === "relay.form_question") {
      manifest.forms.push({
        block_id: block.id,
        key: block.props.key,
        label: block.props.label,
        field_type: block.props.field_type,
        required: block.props.required || false,
        options: block.props.options || []
      });
    }

    if (block.type === "relay.source_bundle") {
      manifest.sources.push({
        block_id: block.id,
        kind: "source_bundle",
        source_id: block.props.id || block.id,
        label: block.props.title
      });
    }

    if (block.type === "relay.transcript_segment") {
      manifest.sources.push({
        block_id: block.id,
        kind: "transcript_range",
        source_id: block.props.source,
        start: block.props.start,
        end: block.props.end,
        label: block.props.speaker
      });
    }

    if (block.type === "relay.file_ref") {
      manifest.sources.push({
        block_id: block.id,
        kind: "file_ref",
        source_id: block.props.id,
        uri: block.props.uri,
        label: block.props.label
      });
    }

    if (block.type === "relay.note_ref") {
      manifest.sources.push({
        block_id: block.id,
        kind: "note_ref",
        source_id: block.props.document || block.props.block,
        label: block.props.label
      });
    }

    if (block.type === "relay.url_ref") {
      manifest.sources.push({
        block_id: block.id,
        kind: "url_ref",
        uri: block.props.url,
        label: block.props.label
      });
    }

    collectInlineMentions(block, manifest);
  });

  manifest.mentions = uniqueBy(JSON.stringify, manifest.mentions);
  return manifest;
}

export function toPlainText(node) {
  if (!node) return "";

  if (Array.isArray(node)) {
    return node.map(toPlainText).join("");
  }

  if (node.type === "text") {
    return node.text || "";
  }

  if (node.label && node.type?.startsWith("relay.") && node.type.endsWith("_ref")) {
    return node.label;
  }

  if (Array.isArray(node.content)) {
    return node.content.map(toPlainText).join("");
  }

  return "";
}

function collectInlineMentions(block, manifest) {
  for (const inline of inlineNodes(block.content || [])) {
    if (inline.type === "relay.entity_ref") {
      manifest.mentions.push({
        block_id: block.id,
        kind: "entity",
        id: inline.id,
        label: inline.label
      });
    }
  }
}

function inlineNodes(nodes) {
  const result = [];

  for (const node of nodes) {
    if (!node || typeof node !== "object") continue;

    if ("id" in node && "type" in node && Array.isArray(node.content)) {
      result.push(...inlineNodes(node.content));
      continue;
    }

    result.push(node);

    if (Array.isArray(node.content)) {
      result.push(...inlineNodes(node.content));
    }
  }

  return result;
}

function visitBlocks(blocks, visitor) {
  for (const block of blocks) {
    visitor(block);

    if (Array.isArray(block.content)) {
      const childBlocks = block.content.filter((child) => child && typeof child === "object" && "id" in child && "type" in child);
      visitBlocks(childBlocks, visitor);
    }
  }
}

function uniqueBy(keyFn, items) {
  const seen = new Set();
  const result = [];

  for (const item of items) {
    const key = keyFn(item);

    if (!seen.has(key)) {
      seen.add(key);
      result.push(item);
    }
  }

  return result;
}
