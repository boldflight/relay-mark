//! Link destination normalization exactly as markdown-it 15 performs it
//! (`normalizeLink`, `normalizeLinkText`, `validateLink`, with mdurl 2 and
//! punycode.js 2). CommonMark itself leaves destinations raw; RelayMark's
//! stored hrefs are these normalized forms, so the engine reproduces them.

use crate::json::{js_trim, utf16_len};

const ENCODE_KEEP: &str = ";/?:@&=+$,-_.!~*'()#";
const DECODE_KEEP: &str = ";/?:@&=+$,#%";

/// `md.validateLink`: refuses executable and non-image `data:` schemes.
pub fn validate_link(url: &str) -> bool {
    let lower = js_trim(url).to_lowercase();
    let bad = ["vbscript:", "javascript:", "file:", "data:"].iter().any(|scheme| lower.starts_with(scheme));
    !bad || ["data:image/gif;", "data:image/png;", "data:image/jpeg;", "data:image/webp;"].iter().any(|good| lower.starts_with(good))
}

/// `md.normalizeLink`: punycode hostnames, percent-encode the rest.
pub fn normalize_link(url: &str) -> String {
    let mut parsed = Url::parse(url);
    if let Some(hostname) = parsed.hostname.as_mut().filter(|h| !h.is_empty())
        && parsed.protocol.as_deref().is_none_or(recode_hostname)
        && let Some(ascii) =
            map_domain(hostname, |label| if label.is_ascii() { Some(label.to_owned()) } else { punycode_encode(label).map(|encoded| format!("xn--{encoded}")) })
    {
        *hostname = ascii;
    }
    for part in [&mut parsed.auth, &mut parsed.hostname, &mut parsed.pathname, &mut parsed.search, &mut parsed.hash] {
        if let Some(value) = part.as_mut().filter(|v| !v.is_empty()) {
            *value = encode(value);
        }
    }
    parsed.format()
}

/// `md.normalizeLinkText`: the human-readable form of an autolink.
pub fn normalize_link_text(url: &str) -> String {
    let mut parsed = Url::parse(url);
    if let Some(hostname) = parsed.hostname.as_mut().filter(|h| !h.is_empty())
        && parsed.protocol.as_deref().is_none_or(recode_hostname)
        && let Some(unicode) = map_domain(hostname, |label| match label.strip_prefix("xn--") {
            Some(rest) => punycode_decode(&rest.to_lowercase()),
            None => Some(label.to_owned()),
        })
    {
        *hostname = unicode;
    }
    decode(&parsed.format())
}

fn recode_hostname(protocol: &str) -> bool {
    matches!(protocol, "http:" | "https:" | "mailto:")
}

/// mdurl's `Url`: a lenient Node.js `url.parse` subset.
#[derive(Default)]
struct Url {
    protocol: Option<String>,
    slashes: bool,
    auth: Option<String>,
    port: Option<String>,
    hostname: Option<String>,
    hash: Option<String>,
    search: Option<String>,
    pathname: Option<String>,
}

const NON_HOST: &[char] = &['%', '/', '?', ';', '#', '\'', '{', '}', '|', '\\', '^', '`', '<', '>', '"', ' ', '\r', '\n', '\t'];

fn hostname_part(part: &str) -> bool {
    utf16_len(part) <= 63 && part.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '_' | '-'))
}

impl Url {
    /// `urlParse(url, slashesDenoteHost = true)`.
    fn parse(url: &str) -> Self {
        let mut this = Url::default();
        let mut rest = js_trim(url).to_owned();
        let proto_len = rest.bytes().take_while(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'+' | b'-')).count();
        let mut lower_proto = None;
        if proto_len > 0 && rest.as_bytes().get(proto_len) == Some(&b':') {
            let proto = rest[..=proto_len].to_owned();
            lower_proto = Some(proto.to_ascii_lowercase());
            rest = rest[proto.len()..].to_owned();
            this.protocol = Some(proto);
        }
        let hostless = this.protocol.as_deref() == Some("javascript:");
        let slashes = rest.starts_with("//");
        if slashes && !hostless {
            rest = rest[2..].to_owned();
            this.slashes = true;
        }
        let slashed = |p: &Option<String>| matches!(p.as_deref(), Some("http:" | "https:" | "ftp:" | "gopher:" | "file:"));
        if !hostless && (slashes || (this.protocol.is_some() && !slashed(&this.protocol))) {
            let host_end = rest.find(['/', '?', '#']);
            let at_sign = match host_end {
                None => rest.rfind('@'),
                Some(end) => rest[..(end + 1).min(rest.len())].rfind('@'),
            };
            if let Some(at) = at_sign {
                this.auth = Some(rest[..at].to_owned());
                rest = rest[at + 1..].to_owned();
            }
            let mut host_end = rest.find(NON_HOST).unwrap_or(rest.len());
            if host_end > 0 && rest.as_bytes()[host_end - 1] == b':' {
                host_end -= 1;
            }
            let host = rest[..host_end].to_owned();
            rest = rest[host_end..].to_owned();
            this.parse_host(&host);
            let mut hostname = this.hostname.take().unwrap_or_default();
            let ipv6 = hostname.starts_with('[') && hostname.ends_with(']');
            if !ipv6 {
                let parts: Vec<String> = hostname.split('.').map(str::to_owned).collect();
                for (i, part) in parts.iter().enumerate() {
                    if part.is_empty() || hostname_part(part) {
                        continue;
                    }
                    let ascii: String =
                        part.chars().flat_map(|c| if (c as u32) > 127 { "x".repeat(c.len_utf16()).chars().collect::<Vec<_>>() } else { vec![c] }).collect();
                    if hostname_part(&ascii) {
                        continue;
                    }
                    let mut valid: Vec<String> = parts[..i].to_vec();
                    let mut not_host: Vec<String> = parts[i + 1..].to_vec();
                    let start: String = part.chars().take_while(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '_' | '-')).collect();
                    let start = if utf16_len(&start) > 63 { start.chars().take(63).collect() } else { start };
                    valid.push(start.clone());
                    not_host.insert(0, part[start.len()..].to_owned());
                    rest = format!("{}{rest}", not_host.join("."));
                    hostname = valid.join(".");
                    break;
                }
            }
            if utf16_len(&hostname) > 255 {
                hostname.clear();
            }
            if ipv6 {
                hostname = hostname[1..hostname.len() - 1].to_owned();
            }
            this.hostname = Some(hostname);
        }
        if let Some(hash) = rest.find('#') {
            this.hash = Some(rest[hash..].to_owned());
            rest.truncate(hash);
        }
        if let Some(query) = rest.find('?') {
            this.search = Some(rest[query..].to_owned());
            rest.truncate(query);
        }
        if !rest.is_empty() {
            this.pathname = Some(rest);
        }
        if slashed(&lower_proto) && this.hostname.as_deref().is_some_and(|h| !h.is_empty()) && this.pathname.is_none() {
            this.pathname = Some(String::new());
        }
        this
    }

    fn parse_host(&mut self, host: &str) {
        let digits = host.bytes().rev().take_while(u8::is_ascii_digit).count();
        let mut host = host;
        if host.len() > digits && host.as_bytes()[host.len() - digits - 1] == b':' {
            if digits > 0 {
                self.port = Some(host[host.len() - digits..].to_owned());
            }
            host = &host[..host.len() - digits - 1];
        }
        if !host.is_empty() {
            self.hostname = Some(host.to_owned());
        }
    }

    fn format(&self) -> String {
        let mut out = String::new();
        out.push_str(self.protocol.as_deref().unwrap_or(""));
        if self.slashes {
            out.push_str("//");
        }
        if let Some(auth) = self.auth.as_deref().filter(|a| !a.is_empty()) {
            out.push_str(auth);
            out.push('@');
        }
        match self.hostname.as_deref() {
            Some(host) if host.contains(':') => {
                out.push('[');
                out.push_str(host);
                out.push(']');
            }
            Some(host) => out.push_str(host),
            None => {}
        }
        if let Some(port) = self.port.as_deref().filter(|p| !p.is_empty()) {
            out.push(':');
            out.push_str(port);
        }
        for part in [&self.pathname, &self.search, &self.hash] {
            out.push_str(part.as_deref().unwrap_or(""));
        }
        out
    }
}

/// mdurl `encode(string)` with its default kept characters and existing
/// escapes retained.
fn encode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    for (index, c) in text.char_indices() {
        if index < i {
            continue;
        }
        if c == '%' && bytes.len() > index + 2 && bytes[index + 1].is_ascii_hexdigit() && bytes[index + 2].is_ascii_hexdigit() {
            out.push_str(&text[index..index + 3]);
            i = index + 3;
            continue;
        }
        if c.is_ascii_alphanumeric() || ENCODE_KEEP.contains(c) {
            out.push(c);
        } else {
            let mut buffer = [0; 4];
            for byte in c.encode_utf8(&mut buffer).bytes() {
                out.push_str(&format!("%{byte:02X}"));
            }
        }
    }
    out
}

/// mdurl `decode(string, ";/?:@&=+$,#%")`: decodes valid UTF-8 escape runs,
/// keeping escapes of the reserved characters and replacing malformed bytes.
fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let hex = |at: usize| -> Option<u32> {
        (bytes.get(at) == Some(&b'%') && bytes.get(at + 1).is_some_and(u8::is_ascii_hexdigit) && bytes.get(at + 2).is_some_and(u8::is_ascii_hexdigit))
            .then(|| u32::from_str_radix(&text[at + 1..at + 3], 16).unwrap_or(0))
    };
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        if hex(i).is_none() {
            let c = text[i..].chars().next().unwrap_or_default();
            out.push(c);
            i += c.len_utf8();
            continue;
        }
        let start = i;
        let mut run = Vec::new();
        while let Some(byte) = hex(i) {
            run.push(byte);
            i += 3;
        }
        let mut j = 0;
        while j < run.len() {
            let b1 = run[j];
            let continuation = |k: usize| run.get(j + k).filter(|b| *b & 0xC0 == 0x80).copied();
            if b1 < 0x80 {
                let c = char::from(b1 as u8);
                if DECODE_KEEP.contains(c) {
                    out.push_str(&text[start + j * 3..start + j * 3 + 3]);
                } else {
                    out.push(c);
                }
                j += 1;
            } else if b1 & 0xE0 == 0xC0 && j + 1 < run.len() && continuation(1).is_some() {
                let code = ((b1 << 6) & 0x7C0) | (run[j + 1] & 0x3F);
                if code < 0x80 {
                    out.push_str("\u{fffd}\u{fffd}")
                } else {
                    out.push(char::from_u32(code).unwrap_or('\u{fffd}'))
                }
                j += 2;
            } else if b1 & 0xF0 == 0xE0 && j + 2 < run.len() && continuation(1).is_some() && continuation(2).is_some() {
                let code = ((b1 << 12) & 0xF000) | ((run[j + 1] << 6) & 0xFC0) | (run[j + 2] & 0x3F);
                if code < 0x800 || (0xD800..=0xDFFF).contains(&code) {
                    out.push_str("\u{fffd}\u{fffd}\u{fffd}")
                } else {
                    out.push(char::from_u32(code).unwrap_or('\u{fffd}'))
                }
                j += 3;
            } else if b1 & 0xF8 == 0xF0 && j + 3 < run.len() && continuation(1).is_some() && continuation(2).is_some() && continuation(3).is_some() {
                let code = ((b1 << 18) & 0x1C_0000) | ((run[j + 1] << 12) & 0x3_F000) | ((run[j + 2] << 6) & 0xFC0) | (run[j + 3] & 0x3F);
                if !(0x1_0000..=0x10_FFFF).contains(&code) {
                    out.push_str("\u{fffd}\u{fffd}\u{fffd}\u{fffd}")
                } else {
                    out.push(char::from_u32(code).unwrap_or('\u{fffd}'))
                }
                j += 4;
            } else {
                out.push('\u{fffd}');
                j += 1;
            }
        }
    }
    out
}

/// punycode.js `mapDomain`: only the part after the first `@` is a domain
/// (and anything after a second `@` is dropped, as there).
fn map_domain(domain: &str, label: impl Fn(&str) -> Option<String>) -> Option<String> {
    let parts: Vec<&str> = domain.split('@').collect();
    let (prefix, domain) = if parts.len() > 1 { (format!("{}@", parts[0]), parts[1]) } else { (String::new(), domain) };
    let domain = domain.replace(['\u{3002}', '\u{FF0E}', '\u{FF61}'], ".");
    let labels = domain.split('.').map(label).collect::<Option<Vec<_>>>()?;
    Some(prefix + &labels.join("."))
}

const BASE: u32 = 36;
const T_MIN: u32 = 1;
const T_MAX: u32 = 26;
const MAX_INT: u32 = 0x7FFF_FFFF;

fn adapt(delta: u32, points: u32, first: bool) -> u32 {
    let mut delta = if first { delta / 700 } else { delta >> 1 };
    delta += delta / points;
    let mut k = 0;
    while delta > ((BASE - T_MIN) * T_MAX) >> 1 {
        delta /= BASE - T_MIN;
        k += BASE;
    }
    k + (BASE - T_MIN + 1) * delta / (delta + 38)
}

fn threshold(k: u32, bias: u32) -> u32 {
    if k <= bias {
        T_MIN
    } else if k >= bias + T_MAX {
        T_MAX
    } else {
        k - bias
    }
}

fn digit_char(digit: u32) -> char {
    char::from(if digit < 26 { b'a' + digit as u8 } else { b'0' + (digit - 26) as u8 })
}

/// RFC 3492 encoding; `None` on overflow (punycode.js throws).
fn punycode_encode(input: &str) -> Option<String> {
    let points: Vec<u32> = input.chars().map(u32::from).collect();
    let mut output: String = input.chars().filter(char::is_ascii).collect();
    let basic = output.chars().count() as u32;
    let mut handled = basic;
    if basic > 0 {
        output.push('-');
    }
    let (mut n, mut delta, mut bias) = (128u32, 0u32, 72u32);
    while (handled as usize) < points.len() {
        let m = points.iter().copied().filter(|p| *p >= n).min()?;
        let plus_one = handled + 1;
        if m - n > (MAX_INT - delta) / plus_one {
            return None;
        }
        delta += (m - n) * plus_one;
        n = m;
        for &point in &points {
            if point < n {
                delta += 1;
                if delta > MAX_INT {
                    return None;
                }
            }
            if point == n {
                let mut q = delta;
                let mut k = BASE;
                loop {
                    let t = threshold(k, bias);
                    if q < t {
                        break;
                    }
                    output.push(digit_char(t + (q - t) % (BASE - t)));
                    q = (q - t) / (BASE - t);
                    k += BASE;
                }
                output.push(digit_char(q));
                bias = adapt(delta, plus_one, handled == basic);
                delta = 0;
                handled += 1;
            }
        }
        delta += 1;
        n += 1;
    }
    Some(output)
}

/// RFC 3492 decoding; `None` where punycode.js throws.
fn punycode_decode(input: &str) -> Option<String> {
    let units: Vec<u32> = input.encode_utf16().map(u32::from).collect();
    let basic = units.iter().rposition(|u| *u == u32::from(b'-')).unwrap_or(0);
    let mut output: Vec<u32> = Vec::new();
    for &unit in &units[..basic] {
        if unit >= 0x80 {
            return None;
        }
        output.push(unit);
    }
    let (mut i, mut n, mut bias) = (0u32, 128u32, 72u32);
    let mut index = if basic > 0 { basic + 1 } else { 0 };
    while index < units.len() {
        let old = i;
        let mut w = 1u32;
        let mut k = BASE;
        loop {
            let unit = *units.get(index)?;
            index += 1;
            let digit = match unit {
                0x30..=0x39 => 26 + unit - 0x30,
                0x41..=0x5A => unit - 0x41,
                0x61..=0x7A => unit - 0x61,
                _ => return None,
            };
            if digit > (MAX_INT - i) / w {
                return None;
            }
            i += digit * w;
            let t = threshold(k, bias);
            if digit < t {
                break;
            }
            if w > MAX_INT / (BASE - t) {
                return None;
            }
            w *= BASE - t;
            k += BASE;
        }
        let out = output.len() as u32 + 1;
        bias = adapt(i - old, out, old == 0);
        if i / out > MAX_INT - n {
            return None;
        }
        n += i / out;
        i %= out;
        output.insert(i as usize, n);
        i += 1;
    }
    output.into_iter().map(char::from_u32).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Expected values are markdown-it 15.0.2's own outputs.
    #[test]
    fn normalizes_like_markdown_it() {
        assert_eq!(normalize_link("/föö"), "/f%C3%B6%C3%B6");
        assert_eq!(normalize_link("/url\\bar*baz"), "/url%5Cbar*baz");
        assert_eq!(normalize_link("https://bücher.de/a b"), "https://xn--bcher-kva.de/a%20b");
        assert_eq!(normalize_link("https://example.com?find=\\*"), "https://example.com?find=%5C*");
        assert_eq!(normalize_link("mailto:foo@bar.example.com"), "mailto:foo@bar.example.com");
        assert_eq!(normalize_link("foo%20b%C3%A4"), "foo%20b%C3%A4");
        assert_eq!(normalize_link_text("https://xn--bcher-kva.de/%C3%A9%2F"), "https://bücher.de/é%2F");
        assert!(!validate_link(" JavaScript:alert(1)"));
        assert!(validate_link("data:image/png;base64,AAAA"));
    }
}
