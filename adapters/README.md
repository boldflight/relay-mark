# RelayMark Adapters

Adapters in this directory are reusable language or platform bridges for the
portable RelayMark contract.

They may:

- Decode and encode RelayMark AST JSON.
- Decode and encode RelayMark manifest JSON.
- Provide generic value types, helpers, and fixture/conformance support.
- Map RelayMark AST to an editor's generic document model when the mapping does
  not depend on a specific product.

They must not:

- Execute Relay actions.
- Know about Relay app routes, permissions, persistence, themes, or LiveView
  hooks.
- Couple to one iOS/macOS app's local cache, action queue, or screen layout.

Client repositories should adapt these generic packages into product behavior.
