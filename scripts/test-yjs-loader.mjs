import {patchHistoryHook} from './yjs-history-hook.mjs';
import {patchHistorySelection} from './y-tiptap-history-selection.mjs';
// Tests consume the same exact-base maintained owner preparation as browser and
// headless builds. Nothing is written to node_modules or another checkout.
export async function load(url,context,nextLoad){
 const result=await nextLoad(url,context);
 if(/\/yjs\/dist\/yjs\.mjs$/.test(url))return{...result,source:patchHistoryHook(Buffer.from(result.source).toString('utf8'))};
 if(/\/@tiptap\/y-tiptap\/dist\/y-tiptap\.js$/.test(url))return{...result,source:patchHistorySelection(Buffer.from(result.source).toString('utf8'))};
 return result;
}
