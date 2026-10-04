// node_modules/lib0/webcrypto.js
var subtle = crypto.subtle;
var getRandomValues = crypto.getRandomValues.bind(crypto);

// node_modules/lib0/random.js
var uint32 = () => getRandomValues(new Uint32Array(1))[0];
var uuidv4Template = "10000000-1000-4000-8000" + -1e11;
var uuidv4 = () => uuidv4Template.replace(
  /[018]/g,
  /** @param {number} c */
  (c) => (c ^ uint32() & 15 >> c / 4).toString(16)
);

// src/owned-command-group.js
function canonicalOperationID(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)) throw TypeError("Invalid owned operation UUID");
  return value;
}
function validateOwnedCommandGroup(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some((k) => !["owner_id", "reference", "operation_ids"].includes(k)) || !Array.isArray(value.operation_ids) || value.operation_ids.length < 1 || value.operation_ids.length > 4096) throw TypeError("Invalid maintained command group");
  canonicalOperationID(value.owner_id);
  value.operation_ids.forEach(canonicalOperationID);
  if (value.reference !== value.operation_ids[0] || new Set(value.operation_ids).size !== value.operation_ids.length) throw TypeError("Invalid maintained command membership");
  return value;
}
function validateOwnedHistory(value) {
  if (!value || !["undo", "redo"].includes(value.kind) || Object.keys(value).some((k) => !["kind", "owner_id", "reference", "operation_ids"].includes(k))) throw TypeError("Invalid owned history");
  validateOwnedCommandGroup({ owner_id: value.owner_id, reference: value.reference, operation_ids: value.operation_ids });
  return value;
}

// adapters/collaboration/owned-command-group.js
var key = "relaymark:operation_ids";
var owners = /* @__PURE__ */ new WeakMap();
function bindOwnedHistoryOwner(manager, ownerID) {
  canonicalOperationID(ownerID);
  if (!manager || !Array.isArray(manager.undoStack) || !Array.isArray(manager.redoStack)) throw TypeError("Unavailable actual history owner");
  const existing = owners.get(manager);
  if (existing && existing !== ownerID) throw TypeError("Conflicting maintained history owner");
  for (const item of [...manager.undoStack, ...manager.redoStack]) {
    const group = item.meta?.get(key);
    if (group && validateOwnedCommandGroup(group).owner_id !== ownerID) throw TypeError("Conflicting maintained history owner");
  }
  owners.set(manager, ownerID);
  return ownerID;
}
function readOwnedHistoryOwner(manager) {
  return owners.get(manager) ?? bindOwnedHistoryOwner(manager, uuidv4());
}
function ownedGroup(manager, item) {
  const group = validateOwnedCommandGroup(item?.meta?.get(key));
  if (group.owner_id !== readOwnedHistoryOwner(manager)) throw TypeError("Conflicting maintained history owner");
  return group;
}
function freeze(group) {
  return Object.freeze({ ...group, operation_ids: Object.freeze(group.operation_ids.slice()) });
}
function bindOwnedCommandGroup(manager, event, operationID) {
  canonicalOperationID(operationID);
  const item = event?.stackItem;
  if (!manager || manager.undoing || manager.redoing || event.type !== "undo" || manager.undoStack.at(-1) !== item || !item?.meta) throw TypeError("Unavailable actual maintained command item");
  const ownerID = readOwnedHistoryOwner(manager), existing = item.meta.get(key), ids = existing ? ownedGroup(manager, item).operation_ids.slice() : [];
  for (const entry of [...manager.undoStack, ...manager.redoStack]) if (entry !== item && entry.meta.get(key) && ownedGroup(manager, entry).operation_ids.includes(operationID)) throw TypeError("Duplicate owned operation UUID");
  if (ids.at(-1) !== operationID) {
    if (ids.includes(operationID)) throw TypeError("Out-of-order owned operation UUID");
    ids.push(operationID);
  }
  const group = validateOwnedCommandGroup({ owner_id: ownerID, reference: ids[0], operation_ids: ids });
  item.meta.set(key, freeze(group));
  return group;
}
function readOwnedCommandGroup(manager, operationID) {
  canonicalOperationID(operationID);
  const item = manager?.undoStack.at(-1);
  if (!item?.meta.get(key)) throw TypeError("No actual owned command group");
  const group = ownedGroup(manager, item);
  if (group.operation_ids.at(-1) !== operationID) throw TypeError("No actual owned command group");
  return { ...group, operation_ids: group.operation_ids.slice() };
}
function bindOwnedCommandHistory(manager, event) {
  const undo = event?.type === "undo", redo = event?.type === "redo";
  if (!manager || event.origin !== manager || !(undo && manager.undoing || redo && manager.redoing)) throw TypeError("Unavailable actual maintained inverse");
  const inverse = (undo ? manager.redoStack : manager.undoStack).at(-1);
  if (!event.stackItem?.meta.get(key) || !inverse?.meta) throw TypeError("Unbound actual owned inverse");
  const group = ownedGroup(manager, event.stackItem);
  inverse.meta.set(key, freeze(group));
  return { kind: event.type, ...group, operation_ids: group.operation_ids.slice() };
}
function prepareOwnedCommandGroup(manager, operationID) {
  canonicalOperationID(operationID);
  if (!manager || manager.undoing || manager.redoing) throw TypeError("Unavailable actual command owner");
  readOwnedHistoryOwner(manager);
  for (const item of [...manager.undoStack, ...manager.redoStack]) if (item.meta.get(key) && ownedGroup(manager, item).operation_ids.includes(operationID)) throw TypeError("Duplicate owned operation UUID");
  const top = manager.undoStack.at(-1), group = top?.meta.get(key) ? ownedGroup(manager, top) : null;
  if (top && (!group || group.operation_ids.length === 4096)) manager.stopCapturing();
}
function prepareOwnedHistory(manager, kind) {
  if (!manager || manager.undoing || manager.redoing || !["undo", "redo"].includes(kind)) throw TypeError("Unavailable actual inverse owner");
  readOwnedHistoryOwner(manager);
  const stack = kind === "undo" ? manager.undoStack : manager.redoStack;
  if (!Array.isArray(stack)) throw TypeError("Unavailable actual inverse stack");
  for (const item of stack) {
    if (!item?.meta?.get(key)) throw TypeError("Unbound actual inverse candidate");
    ownedGroup(manager, item);
  }
  return stack.length > 0;
}
export {
  bindOwnedCommandGroup,
  bindOwnedCommandHistory,
  bindOwnedHistoryOwner,
  prepareOwnedCommandGroup,
  prepareOwnedHistory,
  readOwnedCommandGroup,
  readOwnedHistoryOwner,
  validateOwnedCommandGroup,
  validateOwnedHistory
};
