import {createCollaborationRuntime} from './collaboration-runtime.js'
export {createCollaborationRuntime} from './collaboration-runtime.js'
let defaultRuntime
export function call(command, input) {
  defaultRuntime ||= createCollaborationRuntime()
  return defaultRuntime.call(command, input)
}
// JSON boundary avoids crossing JavaScriptCore object/thread lifetimes into Swift.
globalThis.relayCollaborationCall = (command, json) => JSON.stringify(call(command, JSON.parse(json)))
