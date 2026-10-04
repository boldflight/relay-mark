import { isBlockNode, isInlineNode } from "./node-kind.js";
import { directiveForType } from "./registry.js";

export function projectManifest(document, diagnostics = []) {
  const resourcesByID = new Map(
    (document.resources || []).map((resource) => [resource.id, resource])
  );
  const manifest = {
    type: "relaymark.manifest",
    actions: [],
    mentions: [],
    references: [],
    forms: [],
    sources: [],
    claims: [],
    comparisons: [],
    entity_references: [],
    property_sheets: [],
    data_views: [],
    layouts: [],
    capabilities: [],
    diagnostics
  };

  visitBlocks(document.blocks || [], (block) => {
    const directive = directiveForType(block.type);

    if (directive?.capability) {
      manifest.capabilities.push({
        block_id: block.id,
        id: directive.capability,
        fallback: directive.fallback || "plain_text"
      });
    }

    if (block.type === "relay.entity_reference") {
      manifest.entity_references.push(
        compactObject({
          block_id: block.id,
          id: block.props.id,
          label: block.props.label || trimRelayMarkWhitespace(toPlainText(block)) || undefined,
          projection: block.props.projection || "link"
        })
      );
    }

    if (block.type === "relay.property_sheet") {
      manifest.property_sheets.push(
        compactObject({
          block_id: block.id,
          binding: block.props.binding,
          fields: block.props.fields || [],
          title: block.props.title,
          presentation: block.props.presentation || "stack"
        })
      );
    }

    if (block.type === "relay.data_view") {
      manifest.data_views.push(
        compactObject({
          block_id: block.id,
          source: block.props.source,
          projection: block.props.projection,
          columns: block.props.columns || [],
          filter: block.props.filter,
          sort: block.props.sort || [],
          group: block.props.group,
          limit: block.props.limit,
          title: block.props.title
        })
      );
    }

    if (block.type === "relay.layout") {
      manifest.layouts.push(
        compactObject({
          block_id: block.id,
          mode: block.props.mode || "one_column",
          columns: block.props.columns,
          label: block.props.label
        })
      );
    }

    if (block.type === "relay.action_row") {
      manifest.actions.push(
        compactObject({
          block_id: block.id,
          proposal_id: block.props.proposal_id,
          proposal_record_id: block.props.proposal_record_id,
          proposal_revision: block.props.proposal_revision,
          action: block.props.action,
          target: block.props.target,
          destination: block.props.destination,
          visibility: block.props.visibility,
          review: block.props.review,
          decision_id: block.props.decision_id,
          execution_id: block.props.execution_id,
          undo_id: block.props.undo_id,
          evidence_refs: evidenceRefsFor(block),
          args: {
            ...(block.props.args || {}),
            title: trimRelayMarkWhitespace(toPlainText(block))
          }
        })
      );

      if (typeof block.props.target === "string" && block.props.target.startsWith("entity:")) {
        manifest.mentions.push({
          block_id: block.id,
          kind: "entity",
          id: block.props.target.slice("entity:".length),
          label: block.props.target
        });
      }
    }

    if (block.type === "relay.claim") {
      manifest.claims.push(
        compactObject({
          block_id: block.id,
          key: block.props.key,
          subject: block.props.subject,
          status: block.props.status || "unverified",
          confidence: block.props.confidence,
          evidence_refs: evidenceRefsFor(block),
          text: trimRelayMarkWhitespace(toPlainText(block))
        })
      );
    }

    if (block.type === "relay.comparison") {
      manifest.comparisons.push(
        compactObject({
          block_id: block.id,
          title: block.props.title,
          subjects: block.props.subjects || [],
          criteria: block.props.criteria || [],
          values: block.props.values || {},
          preferred: block.props.preferred,
          layout: block.props.layout || "table",
          evidence_refs: evidenceRefsFor(block),
          summary: trimRelayMarkWhitespace(toPlainText(block))
        })
      );
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
      manifest.sources.push(
        compactObject({
          block_id: block.id,
          kind: "source_bundle",
          source_id: block.props.id,
          bundle_revision: block.props.revision,
          source_hash: block.props.source_hash,
          label: block.props.title
        })
      );
    }

    if (block.type === "relay.evidence_ref") {
      const sourceResource = resourcesByID.get(block.props.source);
      const scriptureRelease =
        block.props.source_type === "scripture" && sourceResource?.type === "scripture"
          ? sourceResource.props
          : undefined;

      manifest.sources.push(
        compactObject({
          block_id: block.id,
          kind: "evidence_ref",
          evidence_id: block.props.id,
          source_id: block.props.source,
          source_type: block.props.source_type,
          source_revision: block.props.source_revision,
          selector: block.props.selector,
          scope: block.props.scope,
          label: block.props.label,
          excerpt: trimRelayMarkWhitespace(toPlainText(block)) || undefined,
          scripture_release: scriptureRelease
        })
      );
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

    collectInlineReferences(block, manifest);
  });

  manifest.mentions = uniqueBy(JSON.stringify, manifest.mentions);
  manifest.references = uniqueBy(JSON.stringify, manifest.references);
  manifest.capabilities = uniqueBy(JSON.stringify, manifest.capabilities);

  for (const key of ["entity_references", "property_sheets", "data_views", "layouts", "capabilities"]) {
    if (manifest[key].length === 0) delete manifest[key];
  }

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

function collectInlineReferences(block, manifest) {
  for (const inline of inlineNodes(block.content || [])) {
    if (inline.type?.startsWith("relay.") && inline.type.endsWith("_ref")) {
      manifest.references.push(
        compactObject({
          block_id: block.id,
          type: inline.type,
          id: inline.id,
          label: inline.label,
          href: inline.href
        })
      );
    }

    if (inline.type === "relay.entity_ref") {
      manifest.mentions.push(
        compactObject({
          block_id: block.id,
          kind: "entity",
          id: inline.id,
          label: inline.label
        })
      );
    }
  }
}

function inlineNodes(nodes) {
  const result = [];

  for (const node of nodes) {
    if (!node || typeof node !== "object") continue;

    if (isBlockNode(node)) {
      continue;
    }

    if (isInlineNode(node)) {
      result.push(node);
    }

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
      const childBlocks = block.content.filter(isBlockNode);
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

function compactObject(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
}

function evidenceRefsFor(block) {
  if (Array.isArray(block.evidence_refs) && block.evidence_refs.length > 0) {
    return block.evidence_refs;
  }

  return Array.isArray(block.props?.evidence) ? block.props.evidence : [];
}

function trimRelayMarkWhitespace(value) {
  return value.replace(
    /^[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+|[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$/gu,
    ""
  );
}
