import { directiveSpecifications } from './directive-registry.js';
const byName = new Map(directiveSpecifications.map(value => [value.name, value]));
const byType = new Map(directiveSpecifications.map(value => [value.ast_type, value]));
export function loadDirectiveRegistry() { return { byName, byType }; }
export function directiveForName(name) { return byName.get(name); }
export function directiveForType(type) { return byType.get(type); }
