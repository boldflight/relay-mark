import {URL} from './document-url.js';
/** Portable inert authored navigation. Hosts still authorize internal destinations. */
export function safeLinkHref(value) {
 if(typeof value!=='string'||!value||/[\s\u0000-\u001f\u007f<>\\]/u.test(value))return false;
 if(value.startsWith('#'))return value.length>1;
 if(value.startsWith('/'))return !value.startsWith('//');
 if(/^https?:\/\//iu.test(value)){try{const url=new URL(value);return !!url.hostname&&!url.username&&!url.password&&['http:','https:'].includes(url.protocol);}catch{return false;}}
 if(/^relay:(?:entity|note|file|tag)\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(value))return true;
 if(/^mailto:/iu.test(value))return value.slice(7).split('?')[0].length>0;
 if(/^tel:/iu.test(value))return /^[+0-9().-]+$/u.test(value.slice(4));
 return false;
}
