# Bounded host link authoring policy v1

This policy governs the first-party native and browser destination-entry controls.
It is not a replacement for the portable XML link grammar, authorization, navigation
policy or stored-document admission. Existing unsupported destinations and metadata
must not be removed or rewritten merely by displaying or editing unrelated text.

New destinations retain their exact input bytes and must satisfy:

- At most 2048 UTF-8 bytes, no raw whitespace, control characters, angle brackets or
  backslash. Every percent escape has two hex digits; decoded text must be UTF-8
  and contain no control characters.
- Absolute HTTP/HTTPS with literal `://`, nonempty host/authority, no userinfo
  (including empty userinfo), and any explicit port in 0...65535. Scheme matching
  is case-insensitive. Encoded spaces and Unicode paths are permitted.
- Lowercase `mailto:` with one decoded ASCII recipient. Local part uses letters,
  digits, dot, underscore, percent, plus or hyphen; no leading/trailing/repeated dot.
  Domain is dot-separated alphanumeric labels, with internal hyphens allowed.
  No fragment or authority. Optional query has only unique `subject` and `body`
  key=value pairs, no empty segments, and ASCII URL-safe value characters
  `A-Za-z0-9=%._~+@-`. The first equals sign separates key from value; raw
  ampersands separate parameters. Empty values are permitted; decoded controls are not.
- Exact lowercase `relay:entity/` followed by a lowercase hyphenated UUID. No
  query, fragment or other suffix. The host still authorizes any navigation; the
  label remains authored text rather than a server-hydrated title.

`link-authoring-policy-v1.json` provides shared positive/negative fixtures, including
Unicode byte boundaries. Consumers may mirror this small file byte-for-byte when
their current package distribution does not ship specification files. This does not
expand v1/v2 mark keys or make the host policy a generic RelayMark parser restriction.
