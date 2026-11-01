/** Canonical physical XML attributes; portable authored attributes remain unchanged.
 * A question node's settings are ONE aggregate `settings` object. Per-key
 * `settings:<key>` fields and the `settings: true` presence marker are never
 * written and are refused when read. */
import {cloneCanonicalJSON as clone} from './canonical-json.js';
import {validateJSONValue} from './document-adapter.js';
import {xmlAttributeEncodingPolicy as policy} from './document-attribute-policy.js';
const perKeyPrefix='settings:',nodes=new Set(policy.nodes),attribute=policy.logical_attribute;
function object(value){if(!value||typeof value!=='object'||Array.isArray(value)||![Object.prototype,null].includes(Object.getPrototypeOf(value)))throw TypeError('Invalid settings attributes');}
function unrelated(attributes){if(Object.keys(attributes).some(key=>key.startsWith(perKeyPrefix))||Object.hasOwn(attributes,attribute))throw TypeError('Settings fields on unrelated node');return attributes;}
export const canonicalAttributeCodec=Object.freeze({
 encode(name,attributes){
  object(attributes);if(!nodes.has(name))return Object.fromEntries(Object.entries(unrelated(attributes)).filter(([,value])=>value!==null));
  const settings=clone(Object.hasOwn(attributes,attribute)?attributes[attribute]:{});object(settings);validateJSONValue(settings);
  if(Object.keys(attributes).some(key=>key.startsWith(perKeyPrefix)))throw TypeError('Physical field supplied as authored attribute');
  const encoded=Object.fromEntries(Object.entries(attributes).filter(([key,value])=>key!==attribute&&value!==null));encoded[attribute]=settings;
  return encoded;
 },
 decode(name,attributes){
  object(attributes);if(!nodes.has(name))return unrelated(attributes);
  if(Object.keys(attributes).some(key=>key.startsWith(perKeyPrefix)))throw TypeError('Per-key physical settings');
  const settings=attributes[attribute];
  if(!Object.hasOwn(attributes,attribute)||!settings||typeof settings!=='object'||Array.isArray(settings))throw TypeError('Aggregate settings required');
  validateJSONValue(settings);return clone(attributes);
 }
});
