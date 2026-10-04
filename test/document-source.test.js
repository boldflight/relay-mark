import test from 'node:test';
import assert from 'node:assert/strict';
import {parseDocument,serializeDocument,projectDocumentMarkdown,renderDocument,importDocument,importDocumentSnapshot,importDocumentSource,validateTextAttributes,documentToSnapshot,snapshotToDocument} from '../src/document-source.js';
test('canonical source imports CommonMark and directives; exact interchange retains metadata and identity',()=>{
 const source='# Title\n\n> **A** and [B](https://example.com)\n\n- [x] Task\n- [ ] Next\n\n| Name | Value |\n| --- | ---: |\n| A | B |\n\n@Callout(tone: "info", emphasis: "soft", title: "Read") {\n![Diagram](/m/asset)\n}\n';
 const ast=parseDocument(source,{namespace:'import-one'});
 assert.deepEqual(parseDocument(source,{namespace:'import-one'}),ast);
 assert.deepEqual(ast.blocks.map(x=>x.type),['heading','quote','task_list','table','relay.callout']);
 assert.equal(ast.blocks[1].content[0].content[0].type,'strong');
 ast.meta={import:'source'};
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);
 assert.match(projectDocumentMarkdown(ast),/\| Name \| Value \|/);
 assert.match(renderDocument(ast),/<strong>A<\/strong>/);
 assert.match(renderDocument(ast),/<div data-callout-title="true">Read<\/div>/);
});

import {readFileSync} from 'node:fs';
test('browser CommonMark maps independent shared IDs and marked leaf expectations',()=>{const fixture=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-source.json',import.meta.url)));assert.deepEqual(parseDocument(fixture.source,{namespace:fixture.namespace}),fixture.expected_ast);});

test('historical form comments import rich labels, original slug choices and settings into canonical nodes',()=>{
 const source='<!-- relay:question id="q1" type="multiple_choice" required="true" points="5" conditional="show-q0" -->\n**Capital?**\n- (x) Paris\n- ( ) London\n<!-- /relay:question -->\n\n<!-- relay:question id="q2" type="short_text" -->\n<!-- /relay:question -->\n';
 const [q1,q2]=parseDocument(source,{namespace:'historic-paper'}).blocks;
 assert.equal(q1.type,'relay.form_question');assert.deepEqual(q1.props,{id:'q1',type:'multiple_choice',required:true,points:5,min:null,max:null,settings:{conditional:'show-q0'}});
 assert.deepEqual(q1.content[0].content,[{type:'strong',content:[{type:'text',text:'Capital?'}]}]);assert.deepEqual(q1.content.slice(1).map(o=>[o.props.id,o.props.correct]),[['paris',true],['london',false]]);assert.equal(q2.props.id,'q2');assert.deepEqual(q2.content[0].content,[]);
});
test('authored renderer rejects executable link schemes instead of emitting clickable HTML',()=>{
 const ast=parseDocument('[Evidence](https://example.com)',{namespace:'safe-link'});
 for(const href of ['javascript:alert(1)','data:text/html,<script>','vbscript:msgbox(1)','//evil.example','https://u:p@example.com']){
  const unsafe=structuredClone(ast);unsafe.blocks[0].content[0].href=href;
  assert.throws(()=>renderDocument(unsafe),/link href/i);
 }
});

import {relayMarkToProseMirror,proseMirrorToRelayMark,identifiedDocumentNodeNames} from '../src/document-adapter.js';
test('generic authored claim evidence and comparison retain Unicode, IDs and table geometry',()=>{
 const ast=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-directives.json',import.meta.url)));
 const pm=relayMarkToProseMirror(ast);assert.deepEqual(pm.content.map(n=>n.type),['relayEvidence','relayClaim','relayComparison']);
 assert.deepEqual(proseMirrorToRelayMark(pm),{type:ast.type,blocks:ast.blocks});
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);assert.match(renderDocument(ast),/<strong>Résumé 世界<\/strong>/);
 assert.match(projectDocumentMarkdown(ast),/@EvidenceRef\(/);assert.match(projectDocumentMarkdown(ast),/\| Subject \| Value \|/);
 const inline=structuredClone(ast);inline.blocks[1].content=inline.blocks[1].content[0].content;assert.throws(()=>relayMarkToProseMirror(inline));
});

test('finite migration wraps historic inline directives once, preserving existing IDs and marks',()=>{
 const canonical=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-directives.json',import.meta.url)));
 const original=structuredClone(canonical);original.version=1;original.blocks[0].content=original.blocks[0].content[0].content;original.blocks[1].evidence_refs=['e-one'];
 const first=importDocument(original,{namespace:'historic-corpus'}),second=importDocument(original,{namespace:'historic-corpus'});
 assert.deepEqual(first,second);assert.deepEqual(original.blocks[0].content,[{type:'emphasis',content:[{type:'text',text:'証拠 café 👩🏽‍💻'}]}]);
 assert.equal(first.document.blocks[0].id,canonical.blocks[0].id);assert.deepEqual(first.document.blocks[0].content[0].content,original.blocks[0].content);
 assert.deepEqual(first.identity_mapping.added,[{id:'bb756b5f57e434fa48ec0d909a25264c1',parent:canonical.blocks[0].id,role:'inline_body',index:0}]);
 assert.deepEqual(importDocument(first.document,{namespace:'historic-corpus'}).document,first.document);
 assert.throws(()=>serializeDocument(original));
});

test('canonical XML construction retains form text ownership and envelope metadata',()=>{
 const ast=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-directives.json',import.meta.url)));
 const xml=documentToSnapshot(ast);assert.deepEqual(xml.metadata,{frontmatter:{},annotations:[],resources:[],meta:{origin:'generic-independent'}});
 assert.deepEqual(xml.children[1].children[0].children,[{kind:'text',delta:[{insert:'Résumé 世界',attributes:{bold:{}}}]}]);
 assert.deepEqual(snapshotToDocument(xml),ast);
 const q=parseDocument('<!-- relay:question id="q" type="multiple_choice" -->\n**Label**\n- ( ) A\n<!-- /relay:question -->',{namespace:'native-question'});
 assert.deepEqual(documentToSnapshot(q).children[0].children.map(n=>n.name),['questionLabel','questionOption']);
 assert.deepEqual(snapshotToDocument(documentToSnapshot(q)),q);
});

test('portable XML materializes community schema defaults for newly inserted native tasks',()=>{
 const ast=parseDocument('- [ ] Task',{namespace:'native-new-task'}),snapshot=documentToSnapshot(ast);
 delete snapshot.children[0].children[0].attributes.entityId;delete snapshot.children[0].children[0].attributes.checked;
 assert.deepEqual(snapshotToDocument(snapshot),ast);
});

test('static linked task and callout expose exact authored hydration attrs without editor identities',()=>{
 const ast=parseDocument('- [ ] Linked task\n\n@Callout(tone: "info", emphasis: "strong") {\nNotice\n}',{namespace:'hydration'});
 ast.blocks[0].content[0].props.entityId='11111111-1111-4111-8111-111111111111';
 const html=renderDocument(ast);
 assert.match(html,/data-relay-task-item="11111111-1111-4111-8111-111111111111"/);
 assert.match(html,/data-authored="[^"\n]*&quot;entityId&quot;:&quot;11111111-1111-4111-8111-111111111111&quot;/);
 assert.match(html,/data-authored="[^"\n]*&quot;tone&quot;:&quot;info&quot;/);
 assert.doesNotMatch(html,/relaymarkId/);
});

test('entity reference titles keep brackets newline quotes and whitespace through shared source and XML',()=>{
 const label=' [A]\n"B"\\ ',id='11111111-1111-4111-8111-111111111111';
 const source=String.raw`[[Person: 11111111-1111-4111-8111-111111111111 | "\u0020\u005b\u0041\u005d\u000a\u0022\u0042\u0022\u005c\u0020"]]`;
 const ast={type:'relaymark.document',blocks:[{id:'b00000000000040008000000000000001',type:'paragraph',content:[{type:'relay.entity_ref',id,label,props:{entityType:'Person',source}}]}]};
 assert.deepEqual(snapshotToDocument(documentToSnapshot(ast)),ast);
 assert.equal(parseDocument(source,{namespace:'reference-title'}).blocks[0].content[0].label,label);
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);
});

test('onboarding static media paths remain authored images through canonical import and XML',()=>{
 for(const src of ['/images/onboarding/connected-note.png','/images/onboarding/connected-work.png']){
  const ast=parseDocument(`![Connected](${src})`,{namespace:'onboarding-image'});
  assert.equal(ast.blocks[0].props.src,src);
  assert.deepEqual(snapshotToDocument(documentToSnapshot(ast)),ast);
  assert.match(renderDocument(ast),new RegExp('src="'+src.replaceAll('.','\\.')+'"'));
 }
});

test('finite historical compact references and linked checkboxes keep identities without creation markers',()=>{
 const source='Contact [[Person:11111111-1111-4111-8111-111111111111|Alex Morgan — Sample]].\n\n[ ] **Review** [[Task:22222222-2222-4222-8222-222222222222]]\n- [x] [[Task:33333333-3333-4333-8333-333333333333]]\n- [ ] Local <!--relay-task-draft:44444444-4444-4444-8444-444444444444-->\n\n`[[Task:44444444-4444-4444-8444-444444444444]]`\n\n```text\n[[Task:44444444-4444-4444-8444-444444444444]]\n```';
 const ast=parseDocument(source,{namespace:'historical-tasks'});
 const fixture=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-historical-source.json',import.meta.url)));assert.equal(source,fixture.source);assert.deepEqual(ast,fixture.expected_ast);
 assert.deepEqual(ast.blocks[0].content[1],{type:'relay.entity_ref',id:'11111111-1111-4111-8111-111111111111',label:'Alex Morgan — Sample',props:{entityType:'Person',source:'[[Person: 11111111-1111-4111-8111-111111111111 | Alex Morgan — Sample]]'}});
 const tasks=ast.blocks[1].content;
 assert.deepEqual(tasks.map(n=>n.props),[{checked:false,entityId:'22222222-2222-4222-8222-222222222222'},{checked:true,entityId:'33333333-3333-4333-8333-333333333333'},{checked:false,entityId:null}]);
 assert.deepEqual(tasks[0].content[0].content,[{type:'strong',content:[{type:'text',text:'Review'}]}]);
 assert.deepEqual(tasks[1].content[0].content,[]);
 assert.deepEqual(tasks[2].content[0].content,[{type:'text',text:'Local'}]);
 assert.equal(ast.blocks[2].content[0].content[0].text,'[[Task:44444444-4444-4444-8444-444444444444]]');
 assert.equal(ast.blocks[3].content[0].text,'[[Task:44444444-4444-4444-8444-444444444444]]\n');
 assert.doesNotMatch(serializeDocument(ast),/draftId|relay-task-draft/);
});

 test('historical raw HTML and invalid wiki tokens remain literal escaped authored text',()=>{
 const source='Before <script>alert(1)</script> [[Person:bad|Title]] after.\n\n<div onclick="evil()">Raw [[Task:bad]]</div>\n';
 const ast=parseDocument(source,{namespace:'literal-html'});
 assert.equal(ast.blocks[0].content.map(n=>n.text).join(''),'Before <script>alert(1)</script> [[Person:bad|Title]] after.');
 assert.equal(ast.blocks[1].content[0].text,'<div onclick="evil()">Raw [[Task:bad]]</div>\n');
 const html=renderDocument(ast);assert.doesNotMatch(html,/<script|<div onclick/);assert.match(html,/&lt;script&gt;alert/);
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);
});

test('callout HTML-looking title remains literal rich title with shared reader marker',()=>{
 const ast=parseDocument('@Callout(title: "<img src=x onerror=alert(1)>", tone: "warning", emphasis: "strong") {\nBody **words**\n}',{namespace:'callout-literal-title'});
 assert.equal(ast.blocks[0].content[0].content[0].text,'<img src=x onerror=alert(1)>');
 assert.match(renderDocument(ast),/<div data-callout-title="true">&lt;img src=x onerror=alert\(1\)&gt;<\/div>/);
});

test('historical EntityRef indentation and bare identity normalize once without losing authored fallback',()=>{
 const id='11111111-1111-4111-8111-111111111111';
 for(const identity of [id,'entity:'+id]){
  const ast=parseDocument(`@EntityRef(id: "${identity}", projection: "card") {\nAuthored fallback\n}`,{namespace:'old-block-ref'});
  assert.deepEqual(ast.blocks[0].props,{id:'entity:'+id,label:'Authored fallback',projection:'card',source:`@EntityRef(id: "entity:${id}", label: "Authored fallback", projection: "card") {\n  Authored fallback\n}`});
  assert.deepEqual(snapshotToDocument(documentToSnapshot(ast)),ast);
 }
});
test('finite historical standalone video and image URL source preserves durable media identity and code literals',()=>{
 const source='::video[/v/11111111-1111-4111-8111-111111111111]\n\nhttps://example.com/a.gif\n\n[https://example.com/b.gif](https://example.com/b.gif)\n\n<https://example.com/c.gif>\n\n`::video[/v/11111111-1111-4111-8111-111111111111]`';
 const ast=parseDocument(source,{namespace:'old-media'});assert.deepEqual(ast.blocks.map(n=>n.type),['relay.video_embed','image','image','image','paragraph']);
 assert.equal(ast.blocks[0].props.videoId,'11111111-1111-4111-8111-111111111111');
 assert.deepEqual(ast.blocks.slice(1,4).map(n=>n.props.src),['https://example.com/a.gif','https://example.com/b.gif','https://example.com/c.gif']);
 assert.equal(ast.blocks[4].content[0].type,'code_span');assert.deepEqual(snapshotToDocument(documentToSnapshot(ast)),ast);
});

test('historical reference normalization refuses duplicate identity or unknown authored attributes',()=>{
 const id='11111111-1111-4111-8111-111111111111';
 for(const attrs of [`id: "${id}", id: "${id}"`,`id: "${id}", surprise: "value"`,`id: "${id}", projection: "popover"`])assert.throws(()=>parseDocument(`@EntityRef(${attrs}) {\nBody\n}`,{namespace:'ambiguous-reference'}));
});

test('historic indented directive examples remain code while the actual prose reference survives',()=>{
 const id='11111111-1111-4111-8111-111111111111',example='22222222-2222-4222-8222-222222222222';
 const source=`@EntityRef(id: "${id}", projection: "chip") {\nReal reference\n}\n\n\`\`\`relaymark\n@EntityRef(id: "${example}") {\nExample\n}\n\`\`\`\n\n    @EntityRef(id: "${example}") {\n    Indented example\n    }\n\n\`[[Person: ${example} | Inline example]]\``;
 const ast=parseDocument(source,{namespace:'reference-code-context'});assert.deepEqual(ast.blocks.map(n=>n.type),['relay.entity_reference','code','code','paragraph']);assert.equal(ast.blocks[0].props.id,'entity:'+id);
 assert.match(ast.blocks[2].content[0].text,/Indented example/);
});

test('historical non-navigation link and unsafe image declarations remain literal without executable hrefs',()=>{
 const source='![Image](relay:entity/11111111-1111-4111-8111-111111111111)\n\n[Query](relay:entity/11111111-1111-4111-8111-111111111111?view=paper)\n[Wrong](relay:entityx/11111111-1111-4111-8111-111111111111)';
 const ast=parseDocument(source,{namespace:'inert-declarations'});assert.equal(ast.blocks[0].type,'paragraph');assert.equal(ast.blocks[0].content[0].text,'![Image](relay:entity/11111111-1111-4111-8111-111111111111)');
 const html=renderDocument(ast);assert.doesNotMatch(html,/<img|<a/);assert.match(html,/\[Query\]/);
});

test('historical task identity at first line survives lazy rich paragraph continuation and repeated context reference',()=>{
 const id='11111111-1111-4111-8111-111111111111';const ast=parseDocument(`- [ ] Keep deleted identity [[Task: ${id}]]\nSee [[Task: ${id} | Deleted task context]] for the decision history.\n`,{namespace:'linked-continuation'});
 const item=ast.blocks[0].content[0];assert.equal(item.props.entityId,id);assert.equal(item.content[0].content.filter(n=>n.type==='relay.entity_ref').length,1);assert.equal(item.content[0].content.find(n=>n.type==='relay.entity_ref').label,'Deleted task context');
 assert.equal(item.content[0].content[0].text,'Keep deleted identity\nSee ');assert.deepEqual(snapshotToDocument(documentToSnapshot(ast)),ast);
});

test('finite XML migration adds identities only and leaves rich peer text and metadata exact',()=>{
 const ast=parseDocument('@FormQuestion(id: "q", type: "multiple_choice") {\n**Choose 🌍**\n@FormOption(id: "paris", correct: false) {\nParis\n}\n}',{namespace:'existing'});
 ast.meta={original:true};const original=documentToSnapshot(ast);
 for(const child of [original.children[0],...original.children[0].children])delete child.attributes.relaymarkId;
 const bytes=JSON.stringify(original),first=importDocumentSnapshot(original,{namespace:'paper-incarnation'}),second=importDocumentSnapshot(original,{namespace:'paper-incarnation'});
 assert.equal(JSON.stringify(original),bytes);assert.deepEqual(first,second);
 assert.equal(first.requires_reconstruction,false);assert.equal(first.normalizations.length,3);
 assert.equal(first.snapshot.children[0].attributes.relaymarkId,'b4295cba87f50493182317a0ad04584a4');
 assert.deepEqual(first.snapshot.children[0].children[1].children,original.children[0].children[1].children);
 assert.deepEqual(first.snapshot.metadata,original.metadata);
 assert.equal(first.document.blocks[0].content[1].props.id,'paris');
 assert.deepEqual(importDocumentSnapshot(first.snapshot,{namespace:'paper-incarnation'}).normalizations,[]);
 const unknown=structuredClone(original);unknown.children[0].name='obsoleteFormEditor';assert.throws(()=>importDocumentSnapshot(unknown,{namespace:'paper-incarnation'}));
 const bad=structuredClone(original);bad.children[0].attributes.options=['lossy'];assert.throws(()=>importDocumentSnapshot(bad,{namespace:'paper-incarnation'}));
});

test('finite exact source import resets historical counters and identities through the same grammar',()=>{
 const old={type:'relaymark.document',version:1,meta:{retained:'original'},blocks:[{id:'old-note',type:'paragraph',content:[{type:'strong',content:[{type:'text',text:'Résumé 🌍'}]}]}]};
 const source='```relaymark-ast\n'+JSON.stringify(old)+'\n```\n';
 assert.throws(()=>parseDocument(source));
 const first=importDocumentSource(source,{namespace:'historical-source'});
 assert.deepEqual(first.document,importDocument(old,{namespace:'historical-source'}).document);
 assert.deepEqual(first.identity_mapping.remapped,[{from:'old-note',to:first.document.blocks[0].id}]);
 assert.equal(first.document.blocks[0].id,'b3caafb0d7c034362851808ae213c59be');assert.equal(first.document.version,undefined);assert.deepEqual(old.meta,{retained:'original'});
 assert.deepEqual(importDocumentSource(source,{namespace:'historical-source'}),first);
});

test('portable identified node owner covers the independently exported production editor schema',()=>{
 const schema=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-editor-schema.json',import.meta.url)));
 assert.deepEqual([...identifiedDocumentNodeNames].sort(),schema.nodes.filter(n=>Object.hasOwn(n.attrs||{},'relaymarkId')).map(n=>n.name).sort());
});

test('canonical typing attributes admit all rich marks and refuse executable links and mixed code',()=>{
 assert.equal(validateTextAttributes({underline:{},highlight:{},superscript:{}}),true);
 const link={href:'https://example.com/evidence',target:'_blank',rel:'noopener noreferrer nofollow',class:null,title:null};
 assert.equal(validateTextAttributes({link,bold:{}}),true);
 for(const attributes of [{code:{},bold:{}},{link:{...link,href:'javascript:alert(1)'}},{underline:{enabled:true}},{unknown:{}}])assert.throws(()=>validateTextAttributes(attributes));
});

test('finite inline media boundary repair preserves rich text, media title and stable independent identities',()=>{
 const f=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/canonical-inline-media.json',import.meta.url)));
 const ast=parseDocument(f.source,{namespace:f.namespace});assert.deepEqual(ast,f.expected_ast);
 assert.deepEqual(parseDocument(serializeDocument(ast)),ast);assert.deepEqual(snapshotToDocument(documentToSnapshot(ast)),ast);
 assert.throws(()=>parseDocument('**before ![diagram](/images/diagram.png) after**',{namespace:f.namespace}),/inline|image/i);
});

test('canonical snapshot projection coalesces real CRDT text segmentation but preserves marks and atoms',async()=>{
 const {snapshotToDocument}=await import('../src/document-source.js');
 const id='b00000000000040008000000000000001';
 const snapshot={kind:'fragment',children:[{kind:'element',name:'paragraph',attributes:{relaymarkId:id},children:[
  {kind:'text',delta:[{insert:'A'},{insert:'🌍Z'}]},
  {kind:'text',delta:[{insert:'B',attributes:{bold:{}}},{insert:'C',attributes:{bold:{}}}]},
  {kind:'element',name:'hardBreak',attributes:{},children:[]},
  {kind:'text',delta:[{insert:'D',attributes:{bold:{}}}]}
 ]}]};
 assert.deepEqual(snapshotToDocument(snapshot),{type:'relaymark.document',blocks:[{id,type:'paragraph',content:[
  {type:'text',text:'A🌍Z'},{type:'strong',content:[{type:'text',text:'BC'}]},{type:'hard_break'},{type:'strong',content:[{type:'text',text:'D'}]}
 ]}]});
});

test('canonical video emits only durable identity and finite import records derived default removals',()=>{
 const ast=parseDocument('Before video\n\n::video[/v/11111111-1111-4111-8111-111111111111]\n\nAfter video',{namespace:'video-current'});
 const snapshot=documentToSnapshot(ast);assert.deepEqual(Object.keys(snapshot.children[1].attributes).sort(),['relaymarkId','videoId']);
 const old=structuredClone(snapshot);old.children[1].attributes.source='mux';old.children[1].attributes.status='ready';assert.throws(()=>snapshotToDocument(old));
 const imported=importDocumentSnapshot(old,{namespace:'video-import'});assert.deepEqual(imported.document,ast);assert.deepEqual(imported.snapshot,snapshot);assert.deepEqual(imported.normalizations,[{path:[1],operation:'remove_attribute',name:'source',before:'mux'},{path:[1],operation:'remove_attribute',name:'status',before:'ready'}]);
 const unknown=structuredClone(old);unknown.children[1].attributes.source='youtube';assert.throws(()=>importDocumentSnapshot(unknown,{namespace:'video-import'}));
});
