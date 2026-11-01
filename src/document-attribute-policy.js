import {canonicalEditorSchema} from './editor-schema.js';
import {canonicalPhysicalSchemaHash} from './document-physical-schema.js';
// Generated from spec/relaymark/xml-attribute-encoding.json.
export const xmlAttributeEncodingPolicy=Object.freeze({"nodes":["questionBlock","questionOption"],"logical_attribute":"settings","value_semantics":"aggregate-json-object","attribute_codec_required":true});
export function physicalAttributeSchemaHash(){return canonicalPhysicalSchemaHash(canonicalEditorSchema,xmlAttributeEncodingPolicy); }
