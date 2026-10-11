import {sha256} from '@noble/hashes/sha2.js';
import {bytesToHex} from '@noble/hashes/utils.js';
/** UTF-8 binary order is the existing wire contract. Valid Unicode scalar
 * order is identical, without locale/ICU or UTF-16 supplementary-key drift. */
function binaryKeyOrder(left,right){
 let i=0,j=0;
 while(i<left.length&&j<right.length){
  const first=left.codePointAt(i),second=right.codePointAt(j);
  if(first!==second)return first<second?-1:1;
  i+=first>0xffff?2:1;j+=second>0xffff?2:1;
 }
 return i<left.length?1:j<right.length?-1:0;
}
function validKey(key){for(const character of key){const point=character.codePointAt(0);if(point>=0xd800&&point<=0xdfff)throw TypeError('Invalid canonical Unicode key');}return key;}

export function equalCanonicalJSON(left, right) {
  return stableStringify(left) === stableStringify(right);
}

export function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }

  if (value && typeof value === "object") {
    const entries = Object.entries(value)
      .filter(([, item]) => item !== undefined)
      .map(([key,item])=>[validKey(key),item])
      .sort(([a], [b]) => binaryKeyOrder(a,b));
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`).join(",")}}`;
  }

  return JSON.stringify(value);
}

/** Copy authored JSON without silently dropping unsupported values. */
export function cloneCanonicalJSON(value){
 if(value===null||typeof value==='string'||typeof value==='boolean')return value;
 if(typeof value==='number'&&Number.isFinite(value))return value;
 if(Array.isArray(value))return value.map(cloneCanonicalJSON);
 if(value&&(Object.getPrototypeOf(value)===Object.prototype||Object.getPrototypeOf(value)===null))return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,cloneCanonicalJSON(item)]));
 throw new TypeError('Invalid authored JSON value');
}

/** Same canonical bytes in browsers and JSCore, without a host serializer. */
export function canonicalJSONSHA256(value){
 const encoded=encodeURIComponent(stableStringify(value)),bytes=[];
 for(let i=0;i<encoded.length;i++){
  if(encoded[i]==='%'){bytes.push(Number.parseInt(encoded.slice(i+1,i+3),16));i+=2;}
  else bytes.push(encoded.charCodeAt(i));
 }
 return bytesToHex(sha256(new Uint8Array(bytes)));
}
