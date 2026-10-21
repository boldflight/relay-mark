import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const supportedKeywords = new Set([
  "$defs",
  "$id",
  "$ref",
  "$schema",
  "additionalProperties",
  "anyOf",
  "const",
  "default",
  "description",
  "enum",
  "items",
  "maximum",
  "maxLength",
  "minimum",
  "minItems",
  "minLength",
  "not",
  "oneOf",
  "pattern",
  "properties",
  "required",
  "title",
  "type",
  "uniqueItems"
]);

export function validateJSONSchema(value, schema, schemaPath) {
  const absoluteSchemaPath = resolve(schemaPath);
  const documents = new Map([[absoluteSchemaPath, schema]]);
  return validateValue(value, schema, {
    documents,
    document: schema,
    documentPath: absoluteSchemaPath,
    instancePath: "",
    schemaPath: "#"
  });
}

function validateValue(value, schema, context) {
  if (schema === true) return [];
  if (schema === false) return [failure(context, "is not allowed by this schema")];
  if (!schema || typeof schema !== "object" || Array.isArray(schema)) {
    throw new TypeError(`Invalid JSON Schema at ${context.schemaPath}.`);
  }

  assertSupportedKeywords(schema, context);

  const errors = [];

  if (typeof schema.$ref === "string") {
    const resolved = resolveReference(schema.$ref, context);
    errors.push(...validateValue(value, resolved.schema, resolved.context));
  }

  if (schema.const !== undefined && !deepEqual(value, schema.const)) {
    errors.push(failure(context, `must equal ${JSON.stringify(schema.const)}`));
  }

  if (Array.isArray(schema.enum) && !schema.enum.some((candidate) => deepEqual(value, candidate))) {
    errors.push(failure(context, `must be one of ${schema.enum.map((item) => JSON.stringify(item)).join(", ")}`));
  }

  if (schema.type && !matchesType(value, schema.type)) {
    errors.push(failure(context, `must be of type ${schema.type}`));
    return errors;
  }

  if (Array.isArray(schema.anyOf)) {
    const matches = schema.anyOf.some((candidate, index) => {
      const candidateContext = withSchemaPath(context, `${context.schemaPath}/anyOf/${index}`);
      return validateValue(value, candidate, candidateContext).length === 0;
    });

    if (!matches) errors.push(failure(context, "must match at least one schema in anyOf"));
  }

  if (Array.isArray(schema.oneOf)) {
    const matchCount = schema.oneOf.filter((candidate, index) => {
      const candidateContext = withSchemaPath(context, `${context.schemaPath}/oneOf/${index}`);
      return validateValue(value, candidate, candidateContext).length === 0;
    }).length;

    if (matchCount !== 1) errors.push(failure(context, "must match exactly one schema in oneOf"));
  }

  if (schema.not !== undefined) {
    const notContext = withSchemaPath(context, `${context.schemaPath}/not`);

    if (validateValue(value, schema.not, notContext).length === 0) {
      errors.push(failure(context, "must not match the schema in not"));
    }
  }

  if (typeof value === "number") {
    if (typeof schema.minimum === "number" && value < schema.minimum) {
      errors.push(failure(context, `must be greater than or equal to ${schema.minimum}`));
    }

    if (typeof schema.maximum === "number" && value > schema.maximum) {
      errors.push(failure(context, `must be less than or equal to ${schema.maximum}`));
    }
  }

  if (typeof value === "string") {
    if (Number.isInteger(schema.minLength) && [...value].length < schema.minLength) {
      errors.push(failure(context, `must contain at least ${schema.minLength} characters`));
    }

    if (Number.isInteger(schema.maxLength) && [...value].length > schema.maxLength) {
      errors.push(failure(context, `must contain at most ${schema.maxLength} characters`));
    }

    if (typeof schema.pattern === "string" && !new RegExp(schema.pattern, "u").test(value)) {
      errors.push(failure(context, `must match pattern ${schema.pattern}`));
    }
  }

  if (Array.isArray(value)) {
    if (Number.isInteger(schema.minItems) && value.length < schema.minItems) {
      errors.push(failure(context, `must contain at least ${schema.minItems} items`));
    }

    if (schema.uniqueItems && new Set(value.map(stableStringify)).size !== value.length) {
      errors.push(failure(context, "must contain unique items"));
    }

    if (schema.items !== undefined) {
      value.forEach((item, index) => {
        const itemContext = {
          ...context,
          instancePath: `${context.instancePath}/${escapePointer(String(index))}`,
          schemaPath: `${context.schemaPath}/items`
        };
        errors.push(...validateValue(item, schema.items, itemContext));
      });
    }
  }

  if (isObject(value)) {
    const properties = isObject(schema.properties) ? schema.properties : {};

    for (const required of schema.required || []) {
      if (!Object.hasOwn(value, required)) {
        errors.push(failure(context, `must contain required property '${required}'`));
      }
    }

    for (const [name, propertySchema] of Object.entries(properties)) {
      if (!Object.hasOwn(value, name)) continue;

      const propertyContext = {
        ...context,
        instancePath: `${context.instancePath}/${escapePointer(name)}`,
        schemaPath: `${context.schemaPath}/properties/${escapePointer(name)}`
      };
      errors.push(...validateValue(value[name], propertySchema, propertyContext));
    }

    const extraProperties = Object.keys(value).filter((name) => !Object.hasOwn(properties, name));

    if (schema.additionalProperties === false) {
      for (const name of extraProperties) {
        errors.push(failure(context, `must not contain additional property '${name}'`));
      }
    } else if (isSchema(schema.additionalProperties)) {
      for (const name of extraProperties) {
        const propertyContext = {
          ...context,
          instancePath: `${context.instancePath}/${escapePointer(name)}`,
          schemaPath: `${context.schemaPath}/additionalProperties`
        };
        errors.push(...validateValue(value[name], schema.additionalProperties, propertyContext));
      }
    }
  }

  return errors;
}

function assertSupportedKeywords(schema, context) {
  for (const keyword of Object.keys(schema)) {
    if (!supportedKeywords.has(keyword)) {
      throw new Error(`Unsupported JSON Schema keyword '${keyword}' at ${context.schemaPath}.`);
    }
  }
}

function resolveReference(reference, context) {
  const hashIndex = reference.indexOf("#");
  const fileReference = hashIndex === -1 ? reference : reference.slice(0, hashIndex);
  const pointer = hashIndex === -1 ? "" : reference.slice(hashIndex + 1);
  const documentPath = fileReference ? resolve(dirname(context.documentPath), fileReference) : context.documentPath;
  let document = context.documents.get(documentPath);

  if (!document) {
    document = JSON.parse(readFileSync(documentPath, "utf8"));
    context.documents.set(documentPath, document);
  }

  const schema = resolvePointer(document, pointer);

  if (schema === undefined) {
    throw new Error(`JSON Schema reference '${reference}' could not be resolved from ${context.documentPath}.`);
  }

  return {
    schema,
    context: {
      ...context,
      document,
      documentPath,
      schemaPath: pointer ? `#${pointer}` : "#"
    }
  };
}

function resolvePointer(document, pointer) {
  if (!pointer) return document;
  if (!pointer.startsWith("/")) return undefined;

  return pointer
    .slice(1)
    .split("/")
    .map(unescapePointer)
    .reduce((value, segment) => value?.[segment], document);
}

function matchesType(value, type) {
  if (type === "null") return value === null;
  if (type === "array") return Array.isArray(value);
  if (type === "object") return isObject(value);
  if (type === "integer") return Number.isInteger(value);
  if (type === "number") return typeof value === "number" && Number.isFinite(value);
  return typeof value === type;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isSchema(value) {
  return value === true || value === false || isObject(value);
}

function withSchemaPath(context, schemaPath) {
  return { ...context, schemaPath };
}

function failure(context, message) {
  return {
    instance_path: context.instancePath || "/",
    schema_path: context.schemaPath,
    message
  };
}

function escapePointer(value) {
  return value.replaceAll("~", "~0").replaceAll("/", "~1");
}

function unescapePointer(value) {
  return value.replaceAll("~1", "/").replaceAll("~0", "~");
}

function deepEqual(left, right) {
  return stableStringify(left) === stableStringify(right);
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;

  if (isObject(value)) {
    return `{${Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`)
      .join(",")}}`;
  }

  return JSON.stringify(value);
}
