import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import * as Source from '../src/document-source.js';
const publication=JSON.parse(readFileSync(new URL('../spec/relaymark/collaboration/fixtures/historical-form-publication.json',import.meta.url)));
test('saved publication migrates rich prose and exact quiz IDs and grading without a current draft',()=>{
 const original=JSON.stringify(publication),result=Source.importFormPublication(publication,{namespace:'publication-proof'}),doc=result.document;
 assert.deepEqual(doc.blocks.map(n=>n.type),['paragraph','relay.callout','relay.form_question','paragraph']);
 assert.equal(doc.blocks[0].content[1].type,'strong');assert.equal(doc.blocks[1].content[0].content[0].text,'Safe guidance');
 const q=doc.blocks[2];assert.equal(q.props.id,'quiz-q');assert.deepEqual(q.props.settings.answer_key,{points:5,correct_answer:'correct-bold-answer'});
 assert.deepEqual(q.content.slice(1).map(n=>[n.props.id,n.props.correct]),[['correct-bold-answer',true],['other-answer',false]]);
 assert.deepEqual(q.content[0].content,[{type:'text',text:'Choose '},{type:'strong',content:[{type:'text',text:'one'}]}]);
 assert.deepEqual(q.content[1].content,[{type:'text',text:'Correct '},{type:'strong',content:[{type:'text',text:'bold'}]},{type:'text',text:' answer'}]);
 assert.equal(JSON.stringify(publication),original);assert.deepEqual(Source.importFormPublication(publication,{namespace:'publication-proof'}),result);
 const conflict=structuredClone(publication);conflict.blocks[1].answer_key.correct_answer='other-answer';assert.throws(()=>Source.importFormPublication(conflict,{namespace:'publication-proof'}));
 const rich=structuredClone(publication);rich.blocks[1].label='First\n\nSecond';assert.throws(()=>Source.importFormPublication(rich,{namespace:'publication-proof'}));
 if(process.env.RELAYMARK_WRITE_PUBLICATION_FIXTURE){const path=new URL('../spec/relaymark/collaboration/fixtures/form-publication-import-expected.json',import.meta.url);import('node:fs').then(fs=>fs.writeFileSync(path,JSON.stringify(result,null,2)+'\n'));}
});

test('same frozen release source recovers omitted settings and refuses conflicts without using a draft',()=>{
 const frozen=publication.blocks[0].label+`\n\n<!-- relay:question id="quiz-q" type="multiple_choice" required="true" points="5" settings='{"placeholder":"Retained label hint"}' -->\nChoose **one**\n- (x) Correct **bold** answer\n- ( ) Other answer\n<!-- /relay:question -->\n\nTrailing instructions`;
 const imported=Source.importFormPublication(publication,{namespace:'publication-proof',source:frozen});
 assert.equal(imported.document.blocks[2].props.settings.placeholder,'Retained label hint');assert.deepEqual(imported.document.blocks[2].props.settings.answer_key,{points:5,correct_answer:'correct-bold-answer'});
 assert.ok(imported.normalizations.some(n=>n.operation==='recover_retained_source_setting'));
 const conflicting=structuredClone(publication);conflicting.blocks[1].settings={placeholder:'Other hint'};assert.throws(()=>Source.importFormPublication(conflicting,{namespace:'publication-proof',source:frozen}));
 assert.throws(()=>Source.importFormPublication(publication,{namespace:'publication-proof',source:frozen.replace('Choose **one**','Changed draft label')}));
 if(process.env.RELAYMARK_WRITE_PUBLICATION_FIXTURE){import('node:fs').then(fs=>fs.writeFileSync(new URL('../spec/relaymark/collaboration/fixtures/form-publication-retained-source.json',import.meta.url),JSON.stringify({source:frozen,expected:imported},null,2)+'\n'));}
});
