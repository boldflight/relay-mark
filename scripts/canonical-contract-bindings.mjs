import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalPhysicalSchemaHash} from '../src/document-physical-schema.js';

const root=fileURLToPath(new URL('..',import.meta.url));
export function prepareContractBindings({contract,editorSchema,attributeEncoding}){
 if(!contract||Object.keys(contract).sort().join(',')!=='contract_version,schema,source_contract'||!Number.isSafeInteger(contract.contract_version)||contract.contract_version<1||typeof contract.schema!=='string'||typeof contract.source_contract!=='string')throw TypeError('Invalid semantic contract input');
 const descriptor={...contract,schema_hash:canonicalPhysicalSchemaHash(editorSchema,attributeEncoding)};
 const annotation='Generated from spec/relaymark/contract.json + editor-schema.json + xml-attribute-encoding.json. Never edit independently.';
 return {descriptor,files:{
  'src/contract.js':'// '+annotation+'\nexport const canonicalContract = Object.freeze('+JSON.stringify(descriptor,null,2)+');\n',
  'adapters/elixir/priv/relaymark/contract.json':JSON.stringify(descriptor,null,2)+'\n',
  'adapters/swift/Sources/RelayMarkSwift/RelayMarkContract.swift':'// '+annotation+'\npublic enum RelayMarkContract {\n    public static let version = '+descriptor.contract_version+'\n    public static let schema = '+JSON.stringify(descriptor.schema)+'\n    public static let sourceContract = '+JSON.stringify(descriptor.source_contract)+'\n    public static let schemaHash = '+JSON.stringify(descriptor.schema_hash)+'\n}\n'
 }};
}
export function verifyContractBindings(input,actual){
 const expected=prepareContractBindings(input);
 for(const [path,source] of Object.entries(expected.files))if(actual[path]!==source)throw TypeError('Canonical contract binding drift: '+path);
 return expected.descriptor;
}
export async function readContractInputs(){
 const read=async path=>JSON.parse(await readFile(resolve(root,path),'utf8'));
 return {contract:await read('spec/relaymark/contract.json'),editorSchema:await read('spec/relaymark/editor-schema.json'),attributeEncoding:await read('spec/relaymark/xml-attribute-encoding.json')};
}
export async function writeContractBindings(destination=root){
 const result=prepareContractBindings(await readContractInputs());
 for(const [path,source]of Object.entries(result.files)){const target=resolve(destination,path);await mkdir(dirname(target),{recursive:true});await writeFile(target,source);}
 return result.descriptor;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv[2]==='--preview')process.stdout.write(JSON.stringify(prepareContractBindings(await readContractInputs()),null,2)+'\n');
 else if(process.argv[2]==='--write'&&process.argv.length===3)await writeContractBindings();
 else throw TypeError('Use --preview or --write for canonical contract source bindings');
}
