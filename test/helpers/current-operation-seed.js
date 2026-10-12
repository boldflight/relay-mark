// Current operations start after an explicit maintained conversion of historical
// seed bytes. Original evidence files and their historical operations stay intact.
import * as Y from 'yjs';
import {prepareAggregateSettingsHistoryCut} from '../../adapters/collaboration/content-edit-mutation.js';
import {prepareAggregateSettingsTransform} from '../../adapters/collaboration/finite-settings-history-cut.js';
export function currentOperationSeed(original) {
  const doc=new Y.Doc({gc:false});
  try {
    Y.applyUpdate(doc,Buffer.from(original,'base64'));
    const transform=prepareAggregateSettingsTransform(doc);
    if (!transform.count) return original;
    let writer=4294900000; while(doc.store.clients.has(writer)) writer--;
    const converted=prepareAggregateSettingsHistoryCut({initial_state_base64:original,current_state_base64:original,receipts:[],owner_id:null,writer_client:writer});
    if (!converted.complete_conversion_mutation_correspondence) throw Error('Unproven fixture conversion');
    return converted.state_base64;
  } finally {doc.destroy();}
}
