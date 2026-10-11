/** Canonical physical XML attributes; portable authored attributes remain unchanged. */
import {cloneCanonicalJSON as clone} from './canonical-json.js';
import {validateJSONValue} from './document-adapter.js';
import btoa from 'core-js-pure/actual/btoa.js';
import atob from 'core-js-pure/actual/atob.js';
import {xmlAttributeEncodingPolicy as policy} from './document-attribute-policy.js';
const prefix=policy.field_prefix,nodes=new Set(policy.nodes),attribute=policy.logical_attribute,presence=policy.presence;
export function settingsAttributeKey(key){
 if(typeof key!=='string')throw TypeError('Invalid authored settings key');
 let encoded;try{encoded=encodeURIComponent(key);}catch{throw TypeError('Invalid authored settings Unicode key');}
 let binary='';for(let i=0;i<encoded.length;i++){if(encoded[i]==='%'){binary+=String.fromCharCode(Number.parseInt(encoded.slice(i+1,i+3),16));i+=2;}else binary+=encoded[i];}
 return prefix+btoa(binary).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
}
function originalKey(field){
 const encoded=field.slice(prefix.length);
 if(!/^[A-Za-z0-9_-]*$/.test(encoded)||encoded.length%4===1)throw TypeError('Invalid physical settings key');
 let key;try{const binary=atob(encoded.replaceAll('-','+').replaceAll('_','/')+'='.repeat((4-encoded.length%4)%4));key=decodeURIComponent(Array.from(binary,v=>'%'+v.charCodeAt(0).toString(16).padStart(2,'0')).join(''));}catch{throw TypeError('Invalid physical settings Unicode key');}
 if(settingsAttributeKey(key)!==field)throw TypeError('Noncanonical physical settings key');
 return key;
}
function object(value){if(!value||typeof value!=='object'||Array.isArray(value)||![Object.prototype,null].includes(Object.getPrototypeOf(value)))throw TypeError('Invalid settings attributes');}
function unrelated(attributes){if(Object.keys(attributes).some(key=>key.startsWith(prefix))||Object.hasOwn(attributes,attribute))throw TypeError('Settings fields on unrelated node');return attributes;}
export const canonicalAttributeCodec=Object.freeze({
 encode(name,attributes){
  object(attributes);if(!nodes.has(name))return Object.fromEntries(Object.entries(unrelated(attributes)).filter(([,value])=>value!==null));
  const settings=clone(Object.hasOwn(attributes,attribute)?attributes[attribute]:{});object(settings);validateJSONValue(settings);
  if(Object.keys(attributes).some(key=>key.startsWith(prefix)))throw TypeError('Physical field supplied as authored attribute');
  const encoded=Object.fromEntries(Object.entries(attributes).filter(([key,value])=>key!==attribute&&value!==null));encoded[attribute]=presence;
  for(const [key,value]of Object.entries(settings))encoded[settingsAttributeKey(key)]=clone(value);
  return encoded;
 },
 decode(name,attributes){
  object(attributes);if(!nodes.has(name))return unrelated(attributes);
  if(!Object.hasOwn(attributes,attribute)||attributes[attribute]!==presence)throw TypeError('Aggregate or missing physical settings');
  const values=[],plain=[];
  for(const [key,value]of Object.entries(attributes)){if(key.startsWith(prefix))values.push([originalKey(key),clone(value)]);else if(key!==attribute)plain.push([key,value]);}
  const settings=Object.fromEntries(values);validateJSONValue(settings);return Object.fromEntries([...plain,[attribute,settings]]);
 }
});
