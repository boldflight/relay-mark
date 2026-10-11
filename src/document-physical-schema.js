import {canonicalJSONSHA256} from './canonical-json.js';

/** Content/physical shape only; callers do not receive admission authority. */
export function canonicalPhysicalSchemaHash(editorSchema,attributeEncoding){
 return canonicalJSONSHA256({editor_schema:editorSchema,xml_attribute_encoding:attributeEncoding});
}
