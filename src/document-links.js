import {URL} from './document-url.js';
import {canonicalEditorSchema} from './editor-schema.js';
// Retain only successful inert HTTP syntax during one synchronous projection.
// No destination authorization or authored attributes enter this bounded scope.
let linkSyntaxScope = null;
export function withLinkSyntaxScope(project) {
 const previous = linkSyntaxScope;
 linkSyntaxScope = {hrefs: new Set(), characters: 0};
 try { return project(); } finally { linkSyntaxScope = previous; }
}
function rememberSafeHTTPHref(value) {
 const scope = linkSyntaxScope;
 if(scope && value.length<=4096 && scope.hrefs.size<256 && scope.characters+value.length<=65536 && !scope.hrefs.has(value)) {
  scope.hrefs.add(value); scope.characters+=value.length;
 }
}
/** Portable inert authored navigation. Hosts still authorize internal destinations. */
export function safeLinkHref(value) {
 if(typeof value!=='string'||!value||/[\s\u0000-\u001f\u007f<>\\]/u.test(value))return false;
 if(value.startsWith('#'))return value.length>1;
 if(value.startsWith('/'))return !value.startsWith('//');
 if(/^https?:\/\//iu.test(value)){
  if(linkSyntaxScope?.hrefs.has(value))return true;
  try{const url=new URL(value);const safe=!!url.hostname&&!url.username&&!url.password&&['http:','https:'].includes(url.protocol);if(safe)rememberSafeHTTPHref(value);return safe;}catch{return false;}
 }
 if(/^relay:(?:entity|note|file|tag)\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(value))return true;
 if(/^mailto:/iu.test(value))return value.slice(7).split('?')[0].length>0;
 if(/^tel:/iu.test(value))return /^[+0-9().-]+$/u.test(value.slice(4));
 return false;
}

/** Durable authored media URI; bytes and access remain host-owned. */
export function safeImageSource(value) {
 if(typeof value!=='string'||value.length>2048||!safeLinkHref(value))return false;
 if(value.startsWith('/')){try{return value.split(/[?#]/u)[0].split('/').every(part=>!['.','..'].includes(decodeURIComponent(part)));}catch{return false;}}
 if(!/^https:\/\//iu.test(value))return false;
 try{return new URL(value).protocol==='https:';}catch{return false;}
}

/** One authored link property owner; the PM schema supplies these exact defaults. */
export const linkDefaults = Object.freeze(Object.fromEntries(Object.entries(canonicalEditorSchema.marks.find(mark=>mark.name==='link').attrs).filter(([name])=>name!=='href').map(([name,spec])=>[name,spec.default])));
export function validateLinkAttributes(attributes) {
 if(!attributes||typeof attributes!=='object'||Array.isArray(attributes)||Object.keys(attributes).some(k=>!['href',...Object.keys(linkDefaults)].includes(k))||!safeLinkHref(attributes.href))throw new TypeError('Invalid link href or attributes');
 for(const key of Object.keys(linkDefaults))if(!Object.hasOwn(attributes,key))throw new TypeError('Missing link '+key);
 const {target,rel,class:className,title}=attributes;
 const invalidText=value=>typeof value!=='string'||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value);
 if(target!==null&&(invalidText(target)||/[\t\r\n]/u.test(target)||(target.startsWith('_')&&!['_blank','_self','_parent','_top'].includes(target.toLowerCase()))))throw new TypeError('Invalid link target');
 if(rel!==null&&invalidText(rel))throw new TypeError('Invalid link rel');
 if(className!==null&&invalidText(className))throw new TypeError('Invalid link class');
 if(title!==null&&invalidText(title))throw new TypeError('Invalid link title');
 return attributes;
}
export function linkAttributes(href,props={}) {
 if(!props||typeof props!=='object'||Array.isArray(props)||Object.keys(props).some(k=>!Object.hasOwn(linkDefaults,k)))throw new TypeError('Unsupported link property');
 return validateLinkAttributes({href,...linkDefaults,...props});
}
export function linkProperties(attributes) {
 validateLinkAttributes(attributes);
 return Object.fromEntries(Object.entries(linkDefaults).filter(([key,value])=>attributes[key]!==value).map(([key])=>[key,attributes[key]]));
}
/** Presentation hardens new browsing contexts without rewriting authored properties. */
export function renderedLinkAttributes(attributes) {
 validateLinkAttributes(attributes);
 const result={...attributes};
 if(![null,'','_self','_parent','_top'].includes(result.target?.toLowerCase()??null)){
  const tokens=(result.rel??'').split(/\s+/u).filter(Boolean);
  for(const token of ['noopener','noreferrer'])if(!tokens.some(x=>x.toLowerCase()===token))tokens.push(token);
  result.rel=tokens.join(' ');
 }
 return result;
}
