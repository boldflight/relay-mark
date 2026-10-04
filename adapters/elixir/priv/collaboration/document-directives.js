/** Generic authored directive nodes from the canonical directive specifications. */
import {directiveForType} from './registry.js';
const definitions=[
 ['relay.source_bundle','relaySourceBundle'],['relay.claim','relayClaim'],['relay.evidence_ref','relayEvidence'],
 ['relay.comparison','relayComparison'],['relay.transcript_segment','relayTranscript'],['relay.action_row','relayAction'],
 ['relay.property_sheet','relayPropertySheet'],['relay.layout','relayLayout'],['relay.file_ref','relayFile'],['relay.note_ref','relayNote'],['relay.url_ref','relayUrl']
];
export const canonicalDirectiveNodes=Object.freeze(definitions.map(([type,name])=>{
 const spec=directiveForType(type);return Object.freeze({type,name,content:spec.children.min>0?'block+':'block*',attributes:spec.attributes,allowed_children:spec.children.allowed_types.filter(t=>t!=='text'&&!t.endsWith('entity_ref')),minimum_children:spec.children.min||0});
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
