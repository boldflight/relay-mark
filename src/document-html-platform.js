// The existing maintained standard API, lexically injected into the DOM worker.
// No global DOM shim or host-dependent decoder is introduced.
import canonicalAtob from 'core-js-pure/actual/atob.js';
export {canonicalAtob as atob};
