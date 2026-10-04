import {patchHistoryHook} from './yjs-history-hook.mjs';
// Tests consume the same exact-base maintained owner preparation as browser and
// headless builds. Nothing is written to node_modules or another checkout.
export async function load(url,context,nextLoad){
 const result=await nextLoad(url,context);
 if(/\/yjs\/dist\/yjs\.mjs$/.test(url))return{...result,source:patchHistoryHook(Buffer.from(result.source).toString('utf8'))};
 return result;
}
