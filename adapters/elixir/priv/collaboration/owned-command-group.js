// src/owned-command-group.js
function canonicalOperationID(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)) throw TypeError("Invalid owned operation UUID");
  return value;
}
function validateOwnedCommandGroup(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some((k) => !["reference", "operation_ids"].includes(k)) || !Array.isArray(value.operation_ids) || value.operation_ids.length < 1 || value.operation_ids.length > 4096) throw TypeError("Invalid maintained command group");
  value.operation_ids.forEach(canonicalOperationID);
  if (value.reference !== value.operation_ids[0] || new Set(value.operation_ids).size !== value.operation_ids.length) throw TypeError("Invalid maintained command membership");
  return value;
}
function validateOwnedHistory(value) {
  if (!value || !["undo", "redo"].includes(value.kind) || Object.keys(value).some((k) => !["kind", "reference", "operation_ids"].includes(k))) throw TypeError("Invalid owned history");
  validateOwnedCommandGroup({ reference: value.reference, operation_ids: value.operation_ids });
  return value;
}

// adapters/collaboration/owned-command-group.js
var key = "relaymark:operation_ids";
function bindOwnedCommandGroup(manager, event, operationID) {
  canonicalOperationID(operationID);
  const item = event?.stackItem;
  if (!manager || manager.undoing || manager.redoing || event.type !== "undo" || manager.undoStack.at(-1) !== item || !item?.meta) throw TypeError("Unavailable actual maintained command item");
  const existing = item.meta.get(key);
  let ids = existing ? validateOwnedCommandGroup({ reference: existing[0], operation_ids: existing }).operation_ids.slice() : [];
  for (const entry of [...manager.undoStack, ...manager.redoStack]) if (entry !== item && entry.meta.get(key)?.includes(operationID)) throw TypeError("Duplicate owned operation UUID");
  if (ids.at(-1) !== operationID) {
    if (ids.includes(operationID)) throw TypeError("Out-of-order owned operation UUID");
    ids.push(operationID);
  }
  const group = validateOwnedCommandGroup({ reference: ids[0], operation_ids: ids });
  item.meta.set(key, Object.freeze(ids));
  return group;
}
function readOwnedCommandGroup(manager, operationID) {
  canonicalOperationID(operationID);
  const item = manager?.undoStack.at(-1), ids = item?.meta.get(key);
  if (!ids || ids.at(-1) !== operationID) throw TypeError("No actual owned command group");
  return validateOwnedCommandGroup({ reference: ids[0], operation_ids: ids.slice() });
}
function bindOwnedCommandHistory(manager, event) {
  const undo = event?.type === "undo", redo = event?.type === "redo";
  if (!manager || event.origin !== manager || !(undo && manager.undoing || redo && manager.redoing)) throw TypeError("Unavailable actual maintained inverse");
  const ids = event.stackItem?.meta.get(key), inverse = (undo ? manager.redoStack : manager.undoStack).at(-1);
  if (!ids || !inverse?.meta) throw TypeError("Unbound actual owned inverse");
  const group = validateOwnedCommandGroup({ reference: ids[0], operation_ids: ids });
  inverse.meta.set(key, Object.freeze(ids.slice()));
  return { kind: event.type, ...group };
}
export {
  bindOwnedCommandGroup,
  bindOwnedCommandHistory,
  readOwnedCommandGroup,
  validateOwnedCommandGroup,
  validateOwnedHistory
};
