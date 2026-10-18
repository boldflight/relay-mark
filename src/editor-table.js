import {TableMap} from 'prosemirror-tables';

/** Canonical table rows require a physical cell. Maintained table commands
 * can cover an empty row entirely by earlier rowspans. The same authored
 * normalization shortens those spans and removes the covered row with actual
 * PM Steps. No received CRDT update is ever rewritten by this command helper.
 */
export function removeCoveredContentEditTableRow(transaction){
 let changed=false;transaction.doc.descendants((table,tablePos)=>{
  if(changed)return false;if(table.type.spec.tableRole!=='table')return true;
  const map=TableMap.get(table);let rowStart=0;
  for(let row=0;row<table.childCount;row++){
   const node=table.child(row);
   if(node.childCount===0&&row>0&&row<map.height){
    const covering=new Set();for(let col=0;col<map.width;col++)covering.add(map.map[row*map.width+col]);
    if([...covering].every(pos=>pos<rowStart)){
     for(const pos of covering){const cell=table.nodeAt(pos);transaction.setNodeMarkup(tablePos+1+pos,null,{...cell.attrs,rowspan:cell.attrs.rowspan-1});}
     transaction.delete(tablePos+1+rowStart,tablePos+1+rowStart+node.nodeSize);changed=true;return false;
    }
   }
   rowStart+=node.nodeSize;
  }
  return true;
 });return changed;
}
