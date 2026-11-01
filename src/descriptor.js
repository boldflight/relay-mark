/** Admission of a stored or received document descriptor: only this runtime's exact canonical contract. */
import {canonicalContract} from './contract.js';
import {equalCanonicalJSON} from './canonical-json.js';

export function admitDescriptor(descriptor){
 if(!equalCanonicalJSON(descriptor,canonicalContract))throw new TypeError('Unsupported document descriptor');
 return {...canonicalContract};
}
