/** Generic authored directive nodes from the canonical directive specifications. */
import {directiveForType} from './registry.js';
const definitions=[
 ['relay.source_bundle','relaySourceBundle'],['relay.claim','relayClaim'],['relay.evidence_ref','relayEvidence'],
 ['relay.comparison','relayComparison'],['relay.transcript_segment','relayTranscript'],['relay.action_row','relayAction'],
 ['relay.property_sheet','relayPropertySheet'],['relay.layout','relayLayout'],['relay.file_ref','relayFile'],['relay.note_ref','relayNote'],['relay.url_ref','relayUrl']
];
const blockNames={paragraph:['paragraph'],heading:['heading'],quote:['blockquote'],list:['bulletList','orderedList'],list_item:['listItem'],task_list:['taskList'],task_item:['taskItem'],code:['codeBlock'],horizontal_rule:['horizontalRule'],image:['image'],table:['table'],table_row:['tableRow'],table_cell:['tableCell','tableHeader'],'relay.callout':['callout'],'relay.callout_title':['calloutTitle'],'relay.video_embed':['videoEmbed'],'relay.entity_reference':['relayEntityReference'],'relay.agent_suggestion':['agentSuggestion'],'relay.data_view':['relayDataView'],'relay.form_question':['questionBlock'],'relay.form_option':['questionOption'],'relay.paper_control':['relayButton','relayAnchor','relayConnection'],...Object.fromEntries(definitions.map(([type,name])=>[type,[name]]))};
export const canonicalDirectiveNodes=Object.freeze(definitions.map(([type,name])=>{
 const spec=directiveForType(type),allowed_children=spec.children.allowed_types,pm_allowed_children=allowed_children.flatMap(t=>{const names=blockNames[t];if(!names)throw new TypeError('Unsupported directive child specification '+t);return names;});
 const expression=pm_allowed_children.length===1?pm_allowed_children[0]:'('+pm_allowed_children.join(' | ')+')';
 return Object.freeze({type,name,content:expression+(spec.children.min>0?'+':'*'),attributes:spec.attributes,allowed_children,pm_allowed_children,minimum_children:spec.children.min||0});
}));
export function directiveNodeForName(name){return canonicalDirectiveNodes.find(n=>n.name===name);}
export function directiveNodeForType(type){return canonicalDirectiveNodes.find(n=>n.type===type);}
export function authoredDirectiveProps(shape,attrs){
 if(!attrs||typeof attrs!=='object'||Array.isArray(attrs))throw new TypeError('Invalid directive attrs');
 for(const key of Object.keys(attrs))if(key!=='relaymarkId'&&!Object.hasOwn(shape.attributes,key))throw new TypeError('Unsupported authored directive field '+key);
 const props={};for(const[key,spec]of Object.entries(shape.attributes)){
  let value=attrs[key];if(value==null){if(Object.hasOwn(spec,'default'))value=spec.default;else if(spec.required)throw new TypeError('Missing authored directive '+key);else continue;}
  const okay=['string','enum'].includes(spec.type)?typeof value==='string':spec.type==='boolean'?typeof value==='boolean':spec.type==='integer'?Number.isSafeInteger(value):spec.type==='number'?typeof value==='number'&&Number.isFinite(value):spec.type==='array'?Array.isArray(value):spec.type==='object'?value&&typeof value==='object'&&!Array.isArray(value):false;
  if(!okay||(spec.type==='enum'&&!spec.values.includes(value))||(spec.items==='string'&&value.some(v=>typeof v!=='string')))throw new TypeError('Invalid authored directive '+key);
  jsonValue(value); props[key]=value;
 }
 return props;
}

function jsonValue(value,depth=0){
 if(depth>64)throw new TypeError('Directive JSON nesting');
 if(value===null||typeof value==='boolean'||typeof value==='string')return;
 if(typeof value==='number'&&Number.isFinite(value))return;
 if(Array.isArray(value)){for(const child of value)jsonValue(child,depth+1);return;}
 if(value&&Object.getPrototypeOf(value)===Object.prototype){for(const child of Object.values(value))jsonValue(child,depth+1);return;}
 throw new TypeError('Invalid directive JSON value');
}
