import {safeImageSource} from './document-links.js';
/** Canonical rich editor projection and strict lossless AST inverse. */
import { directiveNodeForName, directiveNodeForType, authoredDirectiveProps, canonicalDirectiveNodes } from './document-directives.js';
import { mapInline, unmapInline } from './document-inline.js';
import { parseEntityReferenceSource, assertEntityReferenceProps } from './document-reference.js';
import { canonicalPaperControlSource, assertPaperControlProps, paperControlKind, paperControlNodeName } from './document-controls.js';
import { assertAgentSuggestion, assertAgentSuggestionBlock } from './document-suggestion.js';

export const identifiedDocumentNodeNames = Object.freeze(["paragraph", "calloutTitle", "blockquote", "bulletList", "horizontalRule", "orderedList", "listItem", "heading", "taskList", "taskItem", "table", "tableRow", "tableHeader", "tableCell", "codeBlock", "image", "videoEmbed", "relayEntityReference", "agentSuggestion", "callout", "questionBlock", "questionLabel", "questionOption", "relayButton", "relayAnchor", "relayConnection", "relayDataView"].concat(canonicalDirectiveNodes.map(shape => shape.name)));

const blockId = /^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/u;
const alignments = new Set([null, "left", "center", "right"]);
const maxRows = 256;
const maxColumns = 256;
const maxCells = 4096;
const headingId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/u;
const entityId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const maxTaskDepth = 16;
const maxListDepth = 16;
const maxDocumentDepth = 64;
const maxTaskChildren = 4096;

export function tableProseMirrorToRelayMark(prosemirror) {
  const document = proseMirrorToRelayMark(prosemirror);
  if (document.blocks.some(block => block.type !== "table")) {
    throw new TypeError("Table-only projection requires table blocks");
  }
  return document;
}

export function proseMirrorToRelayMark(prosemirror) {
  assertObject(prosemirror, "doc");
  onlyKeys(prosemirror, ["type", "content"], "doc");
  requireType(prosemirror, "doc");
  assertContentDepth(prosemirror);
  const seen = new Set();
  const blocks = children(prosemirror, "doc", 1).map(node => mapBlock(node, seen, 0));
  return { type: "relaymark.document", blocks };
}

export function relayMarkTableToProseMirror(document) {
  const prosemirror = relayMarkToProseMirror(document);
  if (document.blocks.some(block => block.type !== "table")) {
    throw new TypeError("Table-only projection requires table blocks");
  }
  return prosemirror;
}

export function relayMarkToProseMirror(document) {
  assertObject(document, "document");
  onlyKeys(document, ["type", "blocks", "frontmatter", "annotations", "resources", "meta"], "document");
  for (const key of ["frontmatter", "meta"]) if (document[key] !== undefined) assertObject(document[key], key);
  for (const key of ["annotations", "resources"]) if (document[key] !== undefined && !Array.isArray(document[key])) throw new TypeError(`Invalid ${key}`);
  if (document.type !== "relaymark.document") {
    throw new TypeError("Expected a canonical RelayMark AST document");
  }
  assertContentDepth({ content: document.blocks });
  const seen = new Set();
  const blocks = children({ content: document.blocks }, "document", 1);
  return { type: "doc", content: blocks.map(block => unmapBlock(block, seen, 0)) };
}

function mapBlock(node, seen, calloutDepth) {
  const shape=directiveNodeForName(node?.type);
  if(shape){
    checkNode(node,shape.name,seen,Object.keys(shape.attributes));
    const props=authoredDirectiveProps(shape,node.attrs);
    const content=children(node,shape.name,shape.minimum_children).map(child=>mapBlock(child,seen,calloutDepth));
    if(content.some(child=>!shape.allowed_children.includes(child.type)))throw new TypeError('Unsupported authored directive child');
    return {id:node.attrs.relaymarkId,type:shape.type,props,content};
  }
  switch (node?.type) {
    case "paragraph": return mapParagraph(node, seen);
    case "questionBlock": return mapQuestion(node, seen);
    case "relayDataView": return mapDataView(node, seen);
    case "heading": return mapHeading(node, seen);
    case "blockquote": return mapQuote(node, seen, calloutDepth);
    case "bulletList": return mapList(node, seen, false, 0);
    case "orderedList": return mapList(node, seen, true, 0);
    case "taskList": return mapTaskList(node, seen, 0);
    case "codeBlock": return mapCode(node, seen);
    case "horizontalRule": return mapRule(node, seen);
    case "image": return mapImage(node, seen);
    case "videoEmbed": return mapVideo(node, seen);
    case "relayEntityReference": return mapEntityReference(node, seen);
    case "relayButton":
    case "relayAnchor":
    case "relayConnection": return mapPaperControl(node, seen);
    case "agentSuggestion": return mapAgentSuggestion(node, seen);
    case "callout": return mapCallout(node, seen, calloutDepth);
    case "table": {
      const table = mapTable(node, seen);
      validateGrid(table);
      return table;
    }
    default: throw new TypeError(`Unsupported canonical block: ${String(node?.type)}`);
  }
}

function unmapBlock(block, seen, calloutDepth) {
  const shape=directiveNodeForType(block?.type);
  if(shape){
    checkBlock(block,shape.type,seen,true);
    const props=authoredDirectiveProps(shape,block.props||{});
    const body=children(block,shape.type,shape.minimum_children);
    if(body.some(child=>!shape.allowed_children.includes(child.type)))throw new TypeError('Unsupported authored directive child');
    return {type:shape.name,attrs:{relaymarkId:block.id,...props},content:body.map(child=>unmapBlock(child,seen,calloutDepth))};
  }
  switch (block?.type) {
    case "paragraph": return unmapParagraph(block, seen);
    case "relay.form_question": return unmapQuestion(block, seen);
    case "relay.data_view": return unmapDataView(block, seen);
    case "heading": return unmapHeading(block, seen);
    case "quote": return unmapQuote(block, seen, calloutDepth);
    case "list": return unmapList(block, seen, 0);
    case "task_list": return unmapTaskList(block, seen, 0);
    case "code": return unmapCode(block, seen);
    case "horizontal_rule": return unmapRule(block, seen);
    case "image": return unmapImage(block, seen);
    case "relay.video_embed": return unmapVideo(block, seen);
    case "relay.entity_reference": return unmapEntityReference(block, seen);
    case "relay.paper_control": return unmapPaperControl(block, seen);
    case "relay.agent_suggestion": return unmapAgentSuggestion(block, seen);
    case "relay.callout": return unmapCallout(block, seen, calloutDepth);
    case "table": validateGrid(block); return unmapTable(block, seen);
    default: throw new TypeError(`Unsupported canonical block: ${String(block?.type)}`);
  }
}

const calloutTones = new Set(["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"]);
const calloutEmphases = new Set(["soft", "strong"]);

function checkCalloutProps(tone, emphasis) {
  if (!calloutTones.has(tone) || !calloutEmphases.has(emphasis)) {
    throw new TypeError("Unsupported callout tone or emphasis");
  }
}

function mapCallout(node, seen, depth) {
  if (depth >= 8) throw new TypeError("Callout nesting exceeds the draft limit");
  checkNode(node, "callout", seen, ["tone", "emphasis"]);
  const { tone, emphasis } = node.attrs;
  checkCalloutProps(tone, emphasis);
  const items = children(node, "callout", 1);
  if (items[0]?.type === "calloutTitle" && items.length < 2) {
    throw new TypeError("Callout requires a body block");
  }
  return { id: node.attrs.relaymarkId, type: "relay.callout", props: { tone, emphasis },
    content: items.map((item, index) => index === 0 && item.type === "calloutTitle"
      ? mapCalloutTitle(item, seen) : mapBlock(item, seen, depth + 1)) };
}

function unmapCallout(block, seen, depth) {
  if (depth >= 8) throw new TypeError("Callout nesting exceeds the draft limit");
  checkBlock(block, "relay.callout", seen, true);
  assertObject(block.props, "relay.callout.props");
  onlyKeys(block.props, ["tone", "emphasis"], "relay.callout.props");
  const { tone, emphasis } = block.props;
  checkCalloutProps(tone, emphasis);
  const items = children(block, "relay.callout", 1);
  if (items[0]?.type === "relay.callout_title" && items.length < 2) {
    throw new TypeError("Callout requires a body block");
  }
  if (items.slice(1).some(item => item.type === "relay.callout_title")) {
    throw new TypeError("Callout title must be first");
  }
  return { type: "callout", attrs: { relaymarkId: block.id, tone, emphasis },
    content: items.map((item, index) => index === 0 && item.type === "relay.callout_title"
      ? unmapCalloutTitle(item, seen) : unmapBlock(item, seen, depth + 1)) };
}

function mapCalloutTitle(node, seen) {
  checkNode(node, "calloutTitle", seen);
  const items = inlineChildren(node, "calloutTitle");
  if (items.some(item => item.type !== "text")) throw new TypeError("Unsupported callout title inline node");
  return { id: node.attrs.relaymarkId, type: "relay.callout_title",
    content: items.map(mapInline) };
}

function unmapCalloutTitle(block, seen) {
  checkBlock(block, "relay.callout_title", seen);
  const content = inlineChildren(block, "relay.callout_title").map(unmapInline);
  if (content.some(item => item.type !== "text")) throw new TypeError("Unsupported callout title inline node");
  return { type: "calloutTitle", attrs: { relaymarkId: block.id }, content };
}

function mapHeading(node, seen) {
  checkNode(node, "heading", seen, ["level", "headingId"]);
  const { level, headingId: anchor } = node.attrs;
  checkHeading(level, anchor);
  return { id: node.attrs.relaymarkId, type: "heading", props: { level, headingId: anchor },
    content: inlineChildren(node, "heading").map(mapInline) };
}

function unmapHeading(block, seen) {
  checkBlock(block, "heading", seen, true);
  assertObject(block.props, "heading.props");
  onlyKeys(block.props, ["level", "headingId"], "heading.props");
  const { level, headingId: anchor } = block.props;
  checkHeading(level, anchor);
  return { type: "heading", attrs: { relaymarkId: block.id, level, headingId: anchor },
    content: inlineChildren(block, "heading").map(unmapInline) };
}

function checkHeading(level, anchor) {
  if (!Number.isInteger(level) || level < 1 || level > 6 ||
      (anchor !== null && (typeof anchor !== "string" || !headingId.test(anchor)))) {
    throw new TypeError("Invalid heading level or headingId");
  }
}

function mapQuote(node, seen, calloutDepth) {
  checkNode(node, "blockquote", seen);
  return { id: node.attrs.relaymarkId, type: "quote", content: children(node, "blockquote", 1)
    .map(child => mapBlock(child, seen, calloutDepth)) };
}

function unmapQuote(block, seen, calloutDepth) {
  checkBlock(block, "quote", seen);
  return { type: "blockquote", attrs: { relaymarkId: block.id },
    content: children(block, "quote", 1).map(child => unmapBlock(child, seen, calloutDepth)) };
}

function mapList(node, seen, ordered, depth) {
  if (depth >= maxListDepth) throw new TypeError("Unsupported nested list depth");
  checkNode(node, ordered ? "orderedList" : "bulletList", seen, ordered ? ["start", "type"] : []);
  if (ordered && node.attrs.type !== null) throw new TypeError("Unsupported ordered-list type");
  const props = ordered ? { kind: "ordered", start: node.attrs.start } : { kind: "bullet" };
  if (ordered) checkListStart(props.start);
  return { id: node.attrs.relaymarkId, type: "list", props,
    content: children(node, node.type, 1).map(child => mapListItem(child, seen, depth)) };
}

function unmapList(block, seen, depth) {
  if (depth >= maxListDepth) throw new TypeError("Unsupported nested list depth");
  checkBlock(block, "list", seen, true);
  assertObject(block.props, "list.props");
  onlyKeys(block.props, ["kind", "start"], "list.props");
  const ordered = block.props.kind === "ordered";
  if (!ordered && block.props.kind !== "bullet") throw new TypeError("Invalid list kind");
  if (ordered) checkListStart(block.props.start);
  else if (Object.hasOwn(block.props, "start")) throw new TypeError("Bullet list has a start");
  return { type: ordered ? "orderedList" : "bulletList",
    attrs: { relaymarkId: block.id, ...(ordered ? { start: block.props.start, type: null } : {}) },
    content: children(block, "list", 1).map(child => unmapListItem(child, seen, depth)) };
}

function checkListStart(start) {
  if (!Number.isSafeInteger(start) || start < 1) throw new TypeError("Invalid ordered-list start");
}

function mapListItem(node, seen, depth) {
  checkNode(node, "listItem", seen);
  const items = children(node, "listItem", 1);
  if (items[0]?.type !== "paragraph") throw new TypeError("List item must start with a paragraph");
  return { id: node.attrs.relaymarkId, type: "list_item",
    content: [mapParagraph(items[0], seen), ...items.slice(1).map(item =>
      ["bulletList", "orderedList"].includes(item.type)
        ? mapList(item, seen, item.type === "orderedList", depth + 1)
        : mapBlock(item, seen, 0))] };
}

function unmapListItem(block, seen, depth) {
  checkBlock(block, "list_item", seen);
  const items = children(block, "list_item", 1);
  if (items[0]?.type !== "paragraph") throw new TypeError("List item must start with a paragraph");
  return { type: "listItem", attrs: { relaymarkId: block.id },
    content: [unmapParagraph(items[0], seen), ...items.slice(1).map(item =>
      item.type === "list" ? unmapList(item, seen, depth + 1) : unmapBlock(item, seen, 0))] };
}

// Cross-container nesting (for example list/callout/list) has one physical
// depth bound even when its individual container counters restart.
function assertContentDepth(node, depth = 0) {
  if (depth > maxDocumentDepth) throw new TypeError(" document nesting limit exceeded");
  if (Array.isArray(node?.content)) {
    for (const child of node.content) assertContentDepth(child, depth + 1);
  }
}

function checkTaskProps(checked, linkedEntityId) {
  if (typeof checked !== "boolean" ||
      (linkedEntityId !== null && (typeof linkedEntityId !== "string" || !entityId.test(linkedEntityId)))) {
    throw new TypeError("Invalid task checked state or entityId");
  }
}

function taskChildren(items, label) {
  if (items[0]?.type !== "paragraph") {
    throw new TypeError(`Unsupported ${label} children`);
  }
}

function portableTaskChildren(items, label) {
  if (items[0]?.type !== "paragraph") {
    throw new TypeError(`Unsupported ${label} children`);
  }
}

function mapTaskList(node, seen, depth) {
  if (depth >= maxTaskDepth) throw new TypeError("Task list nesting exceeds the draft limit");
  checkNode(node, "taskList", seen);
  const items = children(node, "taskList", 1);
  if (items.length > maxTaskChildren) throw new TypeError("Task list exceeds the draft child limit");
  return { id: node.attrs.relaymarkId, type: "task_list",
    content: items.map(item => mapTaskItem(item, seen, depth)) };
}

function unmapTaskList(block, seen, depth) {
  if (depth >= maxTaskDepth) throw new TypeError("Task list nesting exceeds the draft limit");
  checkBlock(block, "task_list", seen);
  const items = children(block, "task_list", 1);
  if (items.length > maxTaskChildren) throw new TypeError("Task list exceeds the draft child limit");
  return { type: "taskList", attrs: { relaymarkId: block.id },
    content: items.map(item => unmapTaskItem(item, seen, depth)) };
}

function mapTaskItem(node, seen, depth) {
  checkNode(node, "taskItem", seen, ["checked", "entityId"]);
  if (!Object.hasOwn(node.attrs, "checked") || !Object.hasOwn(node.attrs, "entityId")) {
    throw new TypeError("Task item requires normalized checked and entityId attributes");
  }
  checkTaskProps(node.attrs.checked, node.attrs.entityId);
  const items = children(node, "taskItem", 1);
  if (items.length > maxTaskChildren) throw new TypeError("Task item exceeds the draft child limit");
  taskChildren(items, "task item");
  return { id: node.attrs.relaymarkId, type: "task_item",
    props: { checked: node.attrs.checked, entityId: node.attrs.entityId },
    content: items.map(item => item.type === "taskList" ? mapTaskList(item, seen, depth + 1) :
      mapBlock(item, seen, 0)) };
}

function unmapTaskItem(block, seen, depth) {
  checkBlock(block, "task_item", seen, true);
  assertObject(block.props, "task_item.props");
  onlyKeys(block.props, ["checked", "entityId"], "task_item.props");
  if (!Object.hasOwn(block.props, "checked") || !Object.hasOwn(block.props, "entityId")) {
    throw new TypeError("Task item requires checked and entityId props");
  }
  checkTaskProps(block.props.checked, block.props.entityId);
  const items = children(block, "task_item", 1);
  if (items.length > maxTaskChildren) throw new TypeError("Task item exceeds the draft child limit");
  portableTaskChildren(items, "task item");
  return { type: "taskItem", attrs: { relaymarkId: block.id, ...block.props },
    content: items.map(item => item.type === "task_list" ? unmapTaskList(item, seen, depth + 1) :
      unmapBlock(item, seen, 0)) };
}

function mapCode(node, seen) {
  checkNode(node, "codeBlock", seen, ["language"]);
  checkLanguage(node.attrs.language);
  return { id: node.attrs.relaymarkId, type: "code", props: { language: node.attrs.language },
    content: inlineChildren(node, "codeBlock").map(mapText) };
}

function unmapCode(block, seen) {
  checkBlock(block, "code", seen, true);
  assertObject(block.props, "code.props");
  onlyKeys(block.props, ["language"], "code.props");
  checkLanguage(block.props.language);
  return { type: "codeBlock", attrs: { relaymarkId: block.id, language: block.props.language },
    content: inlineChildren(block, "code").map(unmapText) };
}

function checkLanguage(language) {
  if (language !== null && (typeof language !== "string" || /[\r\n]/u.test(language))) {
    throw new TypeError("Invalid code language");
  }
}

function mapRule(node, seen) {
  checkNode(node, "horizontalRule", seen);
  if (node.content !== undefined && children(node, "horizontalRule").length !== 0) {
    throw new TypeError("Horizontal rule cannot have children");
  }
  return { id: node.attrs.relaymarkId, type: "horizontal_rule", content: [] };
}

function unmapRule(block, seen) {
  checkBlock(block, "horizontal_rule", seen);
  if (block.content !== undefined && children(block, "horizontal_rule").length !== 0) {
    throw new TypeError("Horizontal rule cannot have children");
  }
  return { type: "horizontalRule", attrs: { relaymarkId: block.id } };
}

function mapImage(node, seen) {
  checkNode(node, "image", seen, ["src", "alt", "title", "width", "height"]);
  if (node.content !== undefined && children(node, "image").length !== 0) {
    throw new TypeError("Image cannot have children");
  }
  const { src, alt, title, width, height } = node.attrs;
  checkImageProps({ src, alt, title });
  checkDimensions({ width, height });
  const props = { src, alt, title };
  if (width != null) props.width = width;
  if (height != null) props.height = height;
  return { id: node.attrs.relaymarkId, type: "image", props, content: [] };
}

function unmapImage(block, seen) {
  checkBlock(block, "image", seen, true);
  assertObject(block.props, "image.props");
  onlyKeys(block.props, ["src", "alt", "title", "width", "height"], "image.props");
  if (block.content !== undefined && children(block, "image").length !== 0) {
    throw new TypeError("Image cannot have children");
  }
  checkImageProps(block.props);
  checkDimensions(block.props);
  return { type: "image", attrs: { relaymarkId: block.id, width: null, height: null, ...block.props } };
}

function checkImageProps({ src, alt, title }) {
  if (!safeImageSource(src)) throw new TypeError("Image src must be durable local media or HTTPS");
  for (const [name, value] of [["alt", alt], ["title", title]]) {
    if (value !== null && (typeof value !== "string" || value.length > 4096 || /[\r\n]/u.test(value))) {
      throw new TypeError(`Invalid image ${name}`);
    }
  }
}

function mapEntityReference(node, seen) {
  checkNode(node, "relayEntityReference", seen,
    ["entityRef", "entityId", "entityType", "label", "projection", "source"]);
  if (node.content !== undefined && children(node, "relayEntityReference").length !== 0) {
    throw new TypeError("Entity reference atom cannot have children");
  }
  const { entityRef, entityId: id, entityType, label, projection, source } = node.attrs;
  const authored = parseEntityReferenceSource(source);
  if (!authored || authored.id !== entityRef || authored.entityId !== id ||
      entityType !== "Entity" || authored.label !== label || authored.projection !== projection) {
    throw new TypeError("Entity reference source/identity mismatch");
  }
  return { id: node.attrs.relaymarkId, type: "relay.entity_reference",
    props: { id: entityRef, label, projection, source }, content: [] };
}

function unmapEntityReference(block, seen) {
  checkBlock(block, "relay.entity_reference", seen, true);
  if (block.content !== undefined && children(block, "relay.entity_reference").length !== 0) {
    throw new TypeError("Entity reference atom cannot have children");
  }
  const { id, entityId, label, projection, source } = assertEntityReferenceProps(block.props);
  return { type: "relayEntityReference", attrs: { relaymarkId: block.id,
    entityRef: id, entityId, entityType: "Entity", label, projection, source } };
}

const paperControlFields = { button: ["label", "kind", "target"], anchor: ["name"], connection: ["provider"] };

function mapPaperControl(node, seen) {
  const control = paperControlKind(node.type);
  checkNode(node, node.type, seen, paperControlFields[control]);
  if (node.content !== undefined && children(node, node.type).length !== 0) {
    throw new TypeError("Paper control cannot have children");
  }
  const authored = Object.fromEntries(paperControlFields[control].map(field => [field, node.attrs[field]]));
  const source = canonicalPaperControlSource(control, authored);
  return { id: node.attrs.relaymarkId, type: "relay.paper_control",
    props: { control, ...authored, source }, content: [] };
}

function unmapPaperControl(block, seen) {
  checkBlock(block, "relay.paper_control", seen, true);
  if (block.content !== undefined && children(block, "relay.paper_control").length !== 0) {
    throw new TypeError("Paper control cannot have children");
  }
  const { control, authored } = assertPaperControlProps(block.props);
  return { type: paperControlNodeName(control), attrs: { relaymarkId: block.id, ...authored } };
}

function mapAgentSuggestion(node, seen) {
  checkNode(node, 'agentSuggestion', seen, ['review', 'kind', 'confidence', 'evidence', 'content']);
  if (node.content !== undefined && children(node, 'agentSuggestion').length !== 0) {
    throw new TypeError('AgentSuggestion atom cannot have children');
  }
  const { review, kind, confidence, evidence, content } = assertAgentSuggestion(
    node.attrs.review, node.attrs.kind, node.attrs.confidence, node.attrs.evidence, node.attrs.content);
  return { id: node.attrs.relaymarkId, type: 'relay.agent_suggestion',
    props: { review, kind, evidence, ...(confidence === null ? {} : { confidence }) },
    content: [{ type: 'text', text: content }] };
}

function unmapAgentSuggestion(block, seen) {
  checkBlock(block, 'relay.agent_suggestion', seen, true);
  const { review, kind, confidence, evidence, content } = assertAgentSuggestionBlock(block);
  return { type: 'agentSuggestion', attrs: { relaymarkId: block.id,
    review, kind, confidence, evidence, content } };
}

const videoId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const videoDefaults = {
  playbackId: null, title: null, source: "mux", thumbnailUrl: null,
  status: "ready", youtubeId: null, uploadPercent: null
};

function checkVideoId(value) {
  if (typeof value !== "string" || !videoId.test(value)) {
    throw new TypeError("Video ID must be a canonical lowercase UUID");
  }
}

function mapVideo(node, seen) {
  checkNode(node, "videoEmbed", seen, ["videoId", ...Object.keys(videoDefaults)]);
  if (node.content !== undefined && children(node, "videoEmbed").length !== 0) {
    throw new TypeError("Video cannot have children");
  }
  checkVideoId(node.attrs.videoId);
  for (const [key, value] of Object.entries(videoDefaults)) {
    if (node.attrs[key] !== undefined && node.attrs[key] !== value) {
      throw new TypeError(`Video ${key} is presentation metadata`);
    }
  }
  return { id: node.attrs.relaymarkId, type: "relay.video_embed",
    props: { videoId: node.attrs.videoId }, content: [] };
}

function unmapVideo(block, seen) {
  checkBlock(block, "relay.video_embed", seen, true);
  assertObject(block.props, "relay.video_embed.props");
  onlyKeys(block.props, ["videoId"], "relay.video_embed.props");
  if (block.content !== undefined && children(block, "relay.video_embed").length !== 0) {
    throw new TypeError("Video cannot have children");
  }
  checkVideoId(block.props.videoId);
  return { type: "videoEmbed", attrs: { relaymarkId: block.id,
    videoId: block.props.videoId, ...videoDefaults } };
}

function mapTable(node, seen) {
  checkNode(node, "table", seen);
  return { id: node.attrs.relaymarkId, type: "table", content: children(node, "table", 1)
    .map(row => mapRow(row, seen)) };
}

function mapRow(node, seen) {
  checkNode(node, "tableRow", seen);
  return { id: node.attrs.relaymarkId, type: "table_row", content: children(node, "tableRow", 1)
    .map(cell => mapCell(cell, seen)) };
}

function mapCell(node, seen) {
  assertObject(node, "table cell");
  if (node.type !== "tableCell" && node.type !== "tableHeader") {
    throw new TypeError(`Unsupported table child: ${String(node.type)}`);
  }
  checkNode(node, node.type, seen, ["colspan", "rowspan", "colwidth", "align"]);
  const { colspan, rowspan, colwidth, align } = node.attrs;
  checkCellProps({ colspan, rowspan, colwidth, align });
  return {
    id: node.attrs.relaymarkId,
    type: "table_cell",
    props: { header: node.type === "tableHeader", colspan, rowspan, colwidth, align },
    content: children(node, node.type, 1).map(child => mapBlock(child, seen, 0))
  };
}

function mapParagraph(node, seen) {
  checkNode(node, "paragraph", seen);
  return { id: node.attrs.relaymarkId, type: "paragraph", content: inlineChildren(node, "paragraph")
    .map(mapInline) };
}

function mapText(node) {
  assertObject(node, "text");
  onlyKeys(node, ["type", "text"], "text");
  requireType(node, "text");
  if (typeof node.text !== "string" || node.text.length === 0) {
    throw new TypeError("Text must be a nonempty string");
  }
  return { type: "text", text: node.text };
}

function unmapTable(block, seen) {
  checkBlock(block, "table", seen);
  return { type: "table", attrs: { relaymarkId: block.id }, content: children(block, "table", 1)
    .map(row => unmapRow(row, seen)) };
}

function unmapRow(block, seen) {
  checkBlock(block, "table_row", seen);
  return { type: "tableRow", attrs: { relaymarkId: block.id }, content: children(block, "table_row", 1)
    .map(cell => unmapCell(cell, seen)) };
}

function unmapCell(block, seen) {
  checkBlock(block, "table_cell", seen, true);
  const props = block.props;
  assertObject(props, "table_cell.props");
  onlyKeys(props, ["header", "colspan", "rowspan", "colwidth", "align"], "table_cell.props");
  if (typeof props.header !== "boolean") throw new TypeError("table_cell.header must be boolean");
  checkCellProps(props);
  return {
    type: props.header ? "tableHeader" : "tableCell",
    attrs: {
      relaymarkId: block.id,
      colspan: props.colspan,
      rowspan: props.rowspan,
      colwidth: props.colwidth,
      align: props.align
    },
    content: children(block, "table_cell", 1).map(child => unmapBlock(child, seen, 0))
  };
}

function unmapParagraph(block, seen) {
  checkBlock(block, "paragraph", seen);
  return { type: "paragraph", attrs: { relaymarkId: block.id },
    content: inlineChildren(block, "paragraph").map(unmapInline) };
}

function unmapText(node) {
  assertObject(node, "text");
  onlyKeys(node, ["type", "text"], "text");
  requireType(node, "text");
  if (typeof node.text !== "string" || node.text.length === 0) {
    throw new TypeError("Text must be a nonempty string");
  }
  return { type: "text", text: node.text };
}

function checkNode(node, type, seen, additionalAttrs = []) {
  assertObject(node, type);
  onlyKeys(node, ["type", "attrs", "content"], type);
  requireType(node, type);
  assertObject(node.attrs, `${type}.attrs`);
  onlyKeys(node.attrs, ["relaymarkId", ...additionalAttrs], `${type}.attrs`);
  checkId(node.attrs.relaymarkId, seen);
}

function checkBlock(block, type, seen, hasProps = false) {
  assertObject(block, type);
  onlyKeys(block, hasProps ? ["id", "type", "props", "content"] : ["id", "type", "content"], type);
  requireType(block, type);
  checkId(block.id, seen);
}

function checkCellProps(props) {
  if (!Number.isSafeInteger(props.colspan) || props.colspan < 1 ||
      !Number.isSafeInteger(props.rowspan) || props.rowspan < 1) {
    throw new TypeError("Cell spans must be positive safe integers");
  }
  if (props.colwidth !== null &&
      (!Array.isArray(props.colwidth) || props.colwidth.length !== props.colspan ||
       props.colwidth.some(width => !Number.isSafeInteger(width) || width < 0))) {
    throw new TypeError("Cell colwidth must be null or one non-negative width per spanned column");
  }
  if (!alignments.has(props.align)) {
    throw new TypeError("Cell align must be null, left, center, or right");
  }
}

function checkId(id, seen) {
  if (typeof id !== "string" || !blockId.test(id)) throw new TypeError("Missing or invalid relaymarkId");
  if (seen.has(id)) throw new TypeError(`Duplicate relaymarkId: ${id}`);
  seen.add(id);
}

function children(node, label, minimum = 0) {
  if (!Array.isArray(node.content) || node.content.length < minimum) {
    throw new TypeError(`${label} requires an array of at least ${minimum} children`);
  }
  return node.content;
}

function inlineChildren(node, label) {
  if (node.content === undefined) return [];
  return children(node, label);
}

function validateGrid(table) {
  const rows = table.content;
  if (rows.length > maxRows || rows.reduce((count, row) => count + row.content.length, 0) > maxCells) {
    throw new TypeError("Table exceeds the draft row/cell limit");
  }
  const occupied = [];
  let expectedWidth;
  for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    const slots = occupied[rowIndex] || [];
    let column = 0;
    for (const cell of rows[rowIndex].content) {
      while (slots[column]) column++;
      const { colspan, rowspan } = cell.props;
      if (colspan > maxColumns || column + colspan > maxColumns) {
        throw new TypeError("Table exceeds the draft column limit");
      }
      if (rowIndex + rowspan > rows.length) throw new TypeError("Cell rowspan exceeds table rows");
      for (let r = rowIndex; r < rowIndex + rowspan; r++) {
        occupied[r] ||= [];
        for (let c = column; c < column + colspan; c++) {
          if (occupied[r][c]) throw new TypeError("Overlapping table cells");
          occupied[r][c] = true;
        }
      }
      column += colspan;
    }
    const width = occupied[rowIndex].length;
    if (expectedWidth === undefined) expectedWidth = width;
    if (width !== expectedWidth || Array.from({ length: width }, (_, c) => occupied[rowIndex][c]).some(slot => !slot)) {
      throw new TypeError("Table rows must form a complete rectangle");
    }
  }
}

function requireType(node, type) {
  if (node.type !== type) throw new TypeError(`Expected ${type}, got ${String(node.type)}`);
}

function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
}

function onlyKeys(object, allowed, label) {
  for (const key of Object.keys(object)) {
    if (!allowed.includes(key)) throw new TypeError(`Unsupported ${label} field: ${key}`);
  }
}

function checkDimensions(props) {
  for (const key of ["width", "height"]) {
    const value = props[key];
    if (value != null && (!Number.isSafeInteger(value) || value <= 0)) throw new TypeError("Image dimensions must be positive safe integers");
  }
}

const questionFields = ["id", "type", "required", "points", "min", "max", "settings"];
const optionFields = ["id", "correct", "points", "settings"];
const questionTypes = new Set(["short_text","long_text","email","phone","number","multiple_choice","checkboxes","dropdown","linear_scale","date","file_upload","page_break","single_select","multi_select","entity_ref","file","slot_picker","hidden_field","calculated_field","video_question","video_response","payment","payment_block","lightning_payment"]);
export function validateQuestionProps(props, option = false) {
  assertObject(props, "form authored props");
  onlyKeys(props, option ? optionFields : questionFields, "form authored props");
  if (typeof props.id !== "string" || !props.id.trim() || /[\r\n\u0000]/u.test(props.id)) throw new TypeError("Invalid form identity");
  if (option ? typeof props.correct !== "boolean" : (!questionTypes.has(props.type) || typeof props.required !== "boolean")) throw new TypeError("Invalid form type or boolean");
  for (const key of option ? ["points"] : ["points","min","max"]) {
    if (props[key] != null && (typeof props[key] !== "number" || !Number.isFinite(props[key]))) throw new TypeError("Invalid form numeric setting");
  }
  assertObject(props.settings, "form authored settings");
  validateJSONValue(props.settings);
}
function validateJSONValue(value, depth = 0) {
  if (depth > 32) throw new TypeError("Authored settings nesting exceeds bound");
  if (value === null || typeof value === "string" || typeof value === "boolean") return;
  if (typeof value === "number" && Number.isFinite(value)) return;
  if (Array.isArray(value)) { value.forEach(item => validateJSONValue(item, depth + 1)); return; }
  if (value && Object.getPrototypeOf(value) === Object.prototype) { Object.values(value).forEach(item => validateJSONValue(item, depth + 1)); return; }
  throw new TypeError("Authored settings must contain only portable JSON");
}
function formProps(attrs, option) {
  const defaults = option ? {correct:false,points:null,settings:{}} : {required:false,points:null,min:null,max:null,settings:{}};
  const result={...defaults};
  for(const key of option ? optionFields : questionFields) if(attrs[key] !== undefined) result[key]=attrs[key];
  validateQuestionProps(result,option); return result;
}
function mapQuestion(node, seen) {
  checkNode(node,"questionBlock",seen,questionFields);
  const props=formProps(node.attrs,false), parts=children(node,"questionBlock",1);
  checkNode(parts[0],"questionLabel",seen);
  const label={id:parts[0].attrs.relaymarkId,type:"paragraph",content:inlineChildren(parts[0],"questionLabel").map(mapInline)};
  const optionIDs=new Set();
  const options=parts.slice(1).map(option=>{
    checkNode(option,"questionOption",seen,optionFields);
    const props=formProps(option.attrs,true);
    if(optionIDs.has(props.id)) throw new TypeError("Duplicate option identity"); optionIDs.add(props.id);
    return {id:option.attrs.relaymarkId,type:"relay.form_option",props,content:inlineChildren(option,"questionOption").map(mapInline)};
  });
  return {id:node.attrs.relaymarkId,type:"relay.form_question",props,content:[label,...options]};
}
function unmapQuestion(block, seen) {
  checkBlock(block,"relay.form_question",seen,true);
  const props=formProps(block.props,false),parts=children(block,"relay.form_question",1);
  const label=unmapParagraph(parts[0],seen);label.type="questionLabel";
  const optionIDs=new Set();
  const options=parts.slice(1).map(option=>{
    checkBlock(option,"relay.form_option",seen,true);const props=formProps(option.props,true);
    if(optionIDs.has(props.id)) throw new TypeError("Duplicate option identity"); optionIDs.add(props.id);
    return {type:"questionOption",attrs:{relaymarkId:option.id,...props},content:inlineChildren(option,"relay.form_option").map(unmapInline)};
  });
  return {type:"questionBlock",attrs:{relaymarkId:block.id,...props},content:[label,...options]};
}
const dataViewFields=["source","projection","columns","filter","sort","group","limit","title"];
function dataViewProps(attrs) {
  const props={};for(const key of dataViewFields) if(attrs[key]!=null) props[key]=attrs[key];
  if(typeof props.source!=="string" || !/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/u.test(props.source) || !["list","table","feed","calendar","kanban","chart"].includes(props.projection)) throw new TypeError("Invalid data view source/projection");
  for(const key of ["columns","sort"]) if(props[key]!==undefined && (!Array.isArray(props[key]) || props[key].some(v=>typeof v!=="string"))) throw new TypeError("Invalid data view keys");
  if(props.filter!==undefined){assertObject(props.filter,"data view filter");
    const scalar=v=>v===null||typeof v==="string"||typeof v==="boolean"||(typeof v==="number"&&Number.isFinite(v));
    for(const [key,value]of Object.entries(props.filter)) if(!/^[a-z][a-z0-9_]*$/u.test(key)||!(scalar(value)||(Array.isArray(value)&&value.every(scalar))))throw new TypeError("Invalid declarative data view filter");
  }
  if(props.group!==undefined && (typeof props.group!=="string" || !/^[a-z][a-z0-9_]*$/u.test(props.group))) throw new TypeError("Invalid data view group");
  if(props.limit!==undefined && (!Number.isSafeInteger(props.limit) || props.limit<1 || props.limit>1000)) throw new TypeError("Invalid data view limit");
  if(props.title!==undefined && typeof props.title!=="string") throw new TypeError("Invalid data view title");
  return props;
}
function mapDataView(node,seen) {
  checkNode(node,"relayDataView",seen,dataViewFields);
  if(node.content!==undefined && children(node,"relayDataView").length) throw new TypeError("Data view cannot carry records/children");
  return {id:node.attrs.relaymarkId,type:"relay.data_view",props:dataViewProps(node.attrs),content:[]};
}
function unmapDataView(block,seen) {
  checkBlock(block,"relay.data_view",seen,true);onlyKeys(block.props,dataViewFields,"relay.data_view.props");
  if(children(block,"relay.data_view").length) throw new TypeError("Data view cannot carry records/children");
  return {type:"relayDataView",attrs:{relaymarkId:block.id,...dataViewProps(block.props)}};
}
