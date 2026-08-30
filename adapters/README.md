# RelayMark Adapters

Adapters in this directory are reusable language or platform bridges for the
portable RelayMark contract.

They map the Agent Paper document to runtime values and editors. They do not
own entity headers, navigation, modal or sheet containers, footers, previews,
collection engines, or other host UI.

They may:

- Decode and encode RelayMark AST JSON.
- Decode and encode RelayMark manifest JSON.
- Provide generic value types, helpers, and fixture/conformance support.
- Decode portable Agent Paper binding manifests, renderer capabilities, and
  already-authorized semantic layer contribution metadata.
- Map RelayMark AST to an editor's generic document model when the mapping does
  not depend on a specific product.

They must not:

- Execute Relay actions.
- Know about Relay app routes, permissions, persistence, themes, or LiveView
  hooks.
- Resolve bound values, confer access, carry layer grants, or decide which
  contributions a principal may receive.
- Couple to one iOS/macOS app's local cache, action queue, or screen layout.

Client repositories should adapt these generic packages into product behavior.

Adapters version and publish independently for their package ecosystem. Their
shared compatibility identity is the portable version in
`spec/relaymark/conformance/suite.json`, not equality between a Git/Swift tag
and a Hex package version.
