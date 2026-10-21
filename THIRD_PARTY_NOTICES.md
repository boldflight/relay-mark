# Third-party notices

RelayMark is licensed under either of the [MIT License](LICENSE-MIT) or the
[Apache License, Version 2.0](LICENSE-APACHE), at your option. Parts of this
repository are derived from, or bundle, third-party software under the
licenses below. Those parts remain under their original licenses, and the
notices below must be kept with them.

Dependencies that are fetched by a package manager rather than copied into
this repository (Cargo crates, Hex packages, Swift packages, npm packages used
only by the reference runtime or tests) are covered by their own license files.

## Ported source

These files translate third-party JavaScript into Swift or Rust, keeping the
original names and control flow so behavior can be checked line by line.

| Upstream | Version | License | Ported in |
| --- | --- | --- | --- |
| [prosemirror-model](https://github.com/ProseMirror/prosemirror-model) | 1.25.12 | MIT | `adapters/swift/Sources/RelayMarkModel/PMModel.swift`, `PMStructure.swift`; `crates/relaymark-core/src/pm/model.rs`, `pm/schema.rs`, `html_import/model.rs`, `html_import/parser.rs` |
| [prosemirror-transform](https://github.com/ProseMirror/prosemirror-transform) | 1.12.2 | MIT | `adapters/swift/Sources/RelayMarkModel/PMTransform.swift`, `PMStructure.swift`; `crates/relaymark-core/src/pm/step.rs`, `pm/transform.rs` |
| [prosemirror-state](https://github.com/ProseMirror/prosemirror-state) | 1.4.4 | MIT | `adapters/swift/Sources/RelayMarkModel/PMCommands.swift`; `crates/relaymark-core/src/pm/state.rs` |
| [prosemirror-commands](https://github.com/ProseMirror/prosemirror-commands) | 1.7.2 | MIT | `adapters/swift/Sources/RelayMarkModel/PMCommands.swift`; `crates/relaymark-core/src/pm/commands.rs` |
| [prosemirror-schema-list](https://github.com/ProseMirror/prosemirror-schema-list) | 1.5.1 | MIT | `adapters/swift/Sources/RelayMarkModel/PMCommands.swift`; `crates/relaymark-core/src/pm/commands.rs` |
| [prosemirror-tables](https://github.com/ProseMirror/prosemirror-tables) | 1.8.5 | MIT | `crates/relaymark-core/src/pm/tables.rs`, `pm/state.rs` (`CellSelection`) |
| [Tiptap](https://github.com/ueberdosis/tiptap) (core commands and keymaps) | 3.x | MIT | `adapters/swift/Sources/RelayMarkModel/PMCommands.swift` |
| [Tiptap](https://github.com/ueberdosis/tiptap) (extensions' parseHTML rules) | 3.31.3 | MIT | `crates/relaymark-core/src/html_import/rules.rs` (foreign rules), `src/document-html-foreign.js` |
| [markdown-it](https://github.com/markdown-it/markdown-it) (link normalization) | 15.0.2 | MIT | `crates/relaymark-core/src/mdurl.rs` |
| [mdurl](https://github.com/markdown-it/mdurl) (its `url.parse` follows Node.js) | 2.1.0 | MIT | `crates/relaymark-core/src/mdurl.rs` |
| [punycode.js](https://github.com/mathiasbynens/punycode.js) | 2.3.1 | MIT | `crates/relaymark-core/src/mdurl.rs` |

## Vendored source

These files are copied from a third-party project and maintained here, so the
Swift package can link them into its one Rust library.

| Upstream | Version | License | Vendored in |
| --- | --- | --- | --- |
| [yswift](https://github.com/y-crdt/yswift), through Relay's fork [boldflight/yswift](https://github.com/boldflight/yswift) | fork revision 6c8f3baa6fbd | MIT | `crates/yniffi` (with its `LICENSE`), `adapters/swift/Sources/YSwift`, `adapters/swift/Tests/YSwiftTests` |

## Bundled JavaScript

The generated modules under `adapters/elixir/priv/collaboration/` (built by
`scripts/build-collaboration.mjs`) are the web client's RelayMark runtime;
the Elixir adapter itself runs relaymark-core. Its bundles `document-source.js`
and `document-url.js` include these packages (`editor.js` bundles none; the
host supplies its ProseMirror packages):

| Package | Version | License | Copyright |
| --- | --- | --- | --- |
| prosemirror-model | 1.25.12 | MIT | Marijn Haverbeke and others |
| orderedmap | 2.1.1 | MIT | Marijn Haverbeke and others |
| markdown-it | 15.0.2 | MIT | 2014 Vitaly Puzrin, Alex Kocharin |
| mdurl | 2.1.0 | MIT | 2015 Vitaly Puzrin, Alex Kocharin |
| linkify-it | 6.1.0 | MIT | 2015 Vitaly Puzrin |
| punycode.js | 2.3.1 | MIT | Mathias Bynens |
| uc.micro | 3.0.0 | MIT | Mathias Bynens |
| @noble/hashes | 2.0.1 | MIT | 2022 Paul Miller |
| core-js-pure | 3.50.0 | MIT | 2013–2025 Denis Pushkarev; 2025–2026 CoreJS Company |
| entities | 8.1.0 | BSD-2-Clause | Felix Böhm |

## License texts

### MIT License

Applies to every component above marked MIT. Copyright lines:

- Copyright (C) 2015-2017 by Marijn Haverbeke <marijn@haverbeke.berlin> and
  others (prosemirror-model, prosemirror-transform, prosemirror-state,
  prosemirror-commands, prosemirror-schema-list)
- Copyright (C) 2015-2016 by Marijn Haverbeke <marijnh@gmail.com> and others
  (prosemirror-tables)
- Copyright (C) 2016 by Marijn Haverbeke <marijn@haverbeke.berlin> and others
  (orderedmap)
- Copyright (c) 2023 Kevin Jahns, Bartosz Sypytkowski, Hannes Moser, Aidar
  Nugmanoff, Joseph Heck (yswift)
- Copyright (c) 2025, Tiptap GmbH (Tiptap: the ported core commands and keymaps,
  and the extensions' parseHTML rules)
- Copyright (c) 2014 Vitaly Puzrin, Alex Kocharin (markdown-it)
- Copyright (c) 2015 Vitaly Puzrin, Alex Kocharin (mdurl)
- Copyright Joyent, Inc. and other Node contributors (Node.js `url.parse`, as
  adapted by mdurl; its notice follows below)
- Copyright (c) 2015 Vitaly Puzrin (linkify-it)
- Copyright Mathias Bynens <https://mathiasbynens.be/> (punycode.js, uc.micro)
- Copyright (c) 2022 Paul Miller (https://paulmillr.com) (@noble/hashes)
- Copyright (c) 2013–2025 Denis Pushkarev (zloirock.ru); Copyright (c)
  2025–2026 CoreJS Company (core-js.io) (core-js-pure)

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Node.js `url` (mdurl's `url.parse`, ported in `crates/relaymark-core/src/mdurl.rs`)

mdurl's license carries this notice for its `.parse()`, which is based on
Joyent's Node.js `url` code:

```
Copyright Joyent, Inc. and other Node contributors. All rights reserved.
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
```

### BSD 2-Clause License (entities)

```
Copyright (c) Felix Böhm
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this
list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

THIS IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
