import { directiveForName } from "./registry.js";
import { isBlockNode } from "./node-kind.js";
import { parseV3AtomSource } from "./collaboration-atoms-v3.js";
import { parseV3EntityReferenceSource } from "./collaboration-entity-reference-v3.js";

export function compileParsedDocument(parsed) {
  const allocator = createBlockIdAllocator();
  const diagnostics = [...parsed.diagnostics];
  const blocks = [];

  for (const block of parsed.blocks) {
    blocks.push(compileBlock(block, allocator, diagnostics));
  }

  return {
    document: {
      type: "relaymark.document",
      version: 1,
      frontmatter: parsed.frontmatter,
      blocks,
      annotations: [],
      resources: collectResources(blocks)
    },
    diagnostics
  };
}

function compileBlock(block, allocator, diagnostics) {
  if (block.kind === "heading") {
    return {
      id: allocator.next(),
      type: "heading",
      props: { level: block.level },
      content: parseInline(block.text)
    };
  }

  if (block.kind === "paragraph") {
    return {
      id: allocator.next(),
      type: "paragraph",
      content: parseInline(block.text)
    };
  }

  if (block.kind === "directive") {
    const directive = directiveForName(block.name);

    if (!directive) {
      diagnostics.push({
        level: "critical",
        code: "relaymark.directive.unknown",
        message: `Unknown directive '${block.name}'.`,
        location: { line: block.line, column: 1 }
      });
    }

    const astType = directive?.ast_type || `relay.unknown_${block.name.toLowerCase()}`;
    const props = applyAttributeDefaults(directive, block.attrs);
    if (astType === "relay.entity_reference") {
      const authored = parseV3EntityReferenceSource(block.source);
      if (authored && authored.id === props.id && authored.label === (props.label || authored.body) &&
          authored.projection === props.projection && block.children.length === 1 &&
          block.children[0].kind === "paragraph" && block.children[0].text === authored.body) {
        props.source = block.source;
      }
    }
    const id = allocator.next();
    const title = astType === "relay.callout" ? props.title : undefined;
    if (astType === "relay.callout") delete props.title;
    const titleBlock = typeof title === "string"
      ? { id: allocator.next(), type: "relay.callout_title",
        content: title ? [{ type: "text", text: title }] : [] }
      : null;
    const content = shouldFlattenRawDirectiveContent(astType, block.children)
      ? parseInline(block.children[0].text)
      : block.children.map((child) => compileBlock(child, allocator, diagnostics));
    if (titleBlock) content.unshift(titleBlock);
    const evidenceRefs = Array.isArray(props.evidence) ? props.evidence : [];

    const result = {
      id,
      type: astType,
      props,
      content
    };

    if (evidenceRefs.length > 0) {
      result.evidence_refs = evidenceRefs;
    }

    return result;
  }

  return {
    id: allocator.next(),
    type: "paragraph",
    content: [{ type: "text", text: "" }]
  };
}

function shouldFlattenRawDirectiveContent(astType, children) {
  return (
    [
      "relay.action_row",
      "relay.agent_suggestion",
      "relay.claim",
      "relay.comparison",
      "relay.evidence_ref",
      "relay.transcript_segment"
    ].includes(astType) &&
    children.length === 1 &&
    children[0].kind === "paragraph"
  );
}

function applyAttributeDefaults(directive, attrs) {
  const props = { ...attrs };

  for (const [name, attribute] of Object.entries(directive?.attributes || {})) {
    if (props[name] === undefined && Object.hasOwn(attribute, "default")) {
      props[name] = attribute.default;
    }
  }

  return props;
}

function parseInline(text) {
  const nodes = [];
  const pattern = /\[\[[^\]\r\n]+\]\]|\[([^\]]+)\]\(relay:([a-z_]+)\/([^)]+)\)/g;
  let lastIndex = 0;
  let match;

  while ((match = pattern.exec(text))) {
    const atom = match[0].startsWith("[[") ? parseV3AtomSource(match[0]) : null;
    if (match[0].startsWith("[[") && !atom) continue;
    if (match.index > lastIndex) {
      nodes.push({ type: "text", text: text.slice(lastIndex, match.index) });
    }
    nodes.push(atom || { type: `relay.${match[2]}_ref`, id: match[3], label: match[1] });

    lastIndex = pattern.lastIndex;
  }

  if (lastIndex < text.length || nodes.length === 0) {
    nodes.push({ type: "text", text: text.slice(lastIndex) });
  }

  return nodes.filter((node) => node.type !== "text" || node.text.length > 0);
}

function collectResources(blocks) {
  const resources = new Map();

  visitBlocks(blocks, (block) => {
    if (block.type === "relay.transcript_segment" && typeof block.props?.source === "string") {
      const source = block.props.source;
      const id = source.startsWith("transcript:") ? source.slice("transcript:".length) : source;
      resources.set(id, {
        id,
        type: "transcript",
        uri: source,
        label: "Meeting transcript",
        scope: "private"
      });
    }
  });

  return [...resources.values()];
}

function visitBlocks(blocks, visitor) {
  for (const block of blocks) {
    visitor(block);

    if (Array.isArray(block.content)) {
      const childBlocks = block.content.filter(isBlockNode);
      visitBlocks(childBlocks, visitor);
    }
  }
}

function createBlockIdAllocator() {
  let counter = 1;

  return {
    next() {
      const id = `b${counter}`;
      counter += 1;
      return id;
    }
  };
}
