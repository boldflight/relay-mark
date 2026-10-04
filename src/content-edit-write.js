/** Existing maintained StepMaps choose retention; equal values only check it. */
export function contentEditTextGroups(document){
 const groups=[];
 function visit(node,position){
  let groupIndex=0,group=null;
  node.forEach((child,offset)=>{
   const start=(node.type.name==='doc'?0:position+1)+offset;
   if(child.isText){
    if(!group){group={parent:node.attrs.relaymarkId,index:groupIndex++,position:start,text:''};groups.push(group)}
    group.text+=child.text;
   }else{group=null;visit(child,start);groupIndex++;}
  });
  if(node.inlineContent&&node.content.size===0)groups.push({parent:node.attrs.relaymarkId,index:0,position:position+1,text:''});
 }
 visit(document,-1);return groups;
}
function boundary(text,offset){if(offset>0&&offset<text.length){const a=text.charCodeAt(offset-1),b=text.charCodeAt(offset);if(a>=0xd800&&a<=0xdbff&&b>=0xdc00&&b<=0xdfff)throw TypeError('Causal writer boundary splits Unicode')}}
export function planContentEditTextWrite(prepared,sourceParent,sourceGroup,targetParent,targetGroup,sourceSpan){
 let source=prepared.before_groups[sourceParent+':'+sourceGroup],target=prepared.after_groups[targetParent+':'+targetGroup];
 if(!source||!target)throw TypeError('Causal writer text group unavailable');
 if(sourceSpan!==undefined){
  if(!sourceSpan||Object.keys(sourceSpan).sort().join(',')!=='length,offset'||!Number.isSafeInteger(sourceSpan.offset)||!Number.isSafeInteger(sourceSpan.length)||sourceSpan.offset<0||sourceSpan.length<0||sourceSpan.offset+sourceSpan.length>source.text.length)throw TypeError('Invalid causal source branch span');
  boundary(source.text,sourceSpan.offset);boundary(source.text,sourceSpan.offset+sourceSpan.length);
  source={...source,position:source.position+sourceSpan.offset,text:source.text.slice(sourceSpan.offset,sourceSpan.offset+sourceSpan.length)};
 }
 const kept=[];
 let lower=0,upper=prepared.retained_ranges.length;
 while(lower<upper){const middle=(lower+upper)>>>1,range=prepared.retained_ranges[middle];if(range.source_from+range.length<=source.position)lower=middle+1;else upper=middle;}
 for(let i=lower;i<prepared.retained_ranges.length&&prepared.retained_ranges[i].source_from<source.position+source.text.length;i++){
  const range=prepared.retained_ranges[i];
  const from=Math.max(range.source_from,source.position,range.source_from+target.position-range.destination_from);
  const to=Math.min(range.source_from+range.length,source.position+source.text.length,range.source_from+target.position+target.text.length-range.destination_from);
  if(from<to)kept.push({source:from-source.position,target:range.destination_from+from-range.source_from-target.position,count:to-from});
 }
 kept.sort((a,b)=>a.target-b.target);const delta=[];let from=0,to=0;
 function gaps(nextSource,nextTarget){
  boundary(source.text,from);boundary(source.text,nextSource);boundary(target.text,to);boundary(target.text,nextTarget);
  if(nextSource<from||nextTarget<to)throw TypeError('Causal writer retention order disagrees');
  if(nextSource>from)delta.push({delete:nextSource-from});
  if(nextTarget>to)delta.push({insert:target.text.slice(to,nextTarget)});
 }
 for(const range of kept){gaps(range.source,range.target);boundary(source.text,range.source+range.count);boundary(target.text,range.target+range.count);if(source.text.slice(range.source,range.source+range.count)!==target.text.slice(range.target,range.target+range.count))throw TypeError('Causal writer retained contents disagree');delta.push({retain:range.count});from=range.source+range.count;to=range.target+range.count;}
 gaps(source.text.length,target.text.length);return delta;
}
