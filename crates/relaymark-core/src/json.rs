//! JSON values with the reference runtime's observable behavior: ECMAScript
//! number spelling, `JSON.stringify` escaping and property order, and the
//! canonical sorted encoding used for digests and equality.

use serde_json::{Number, Value};
use sha2::{Digest, Sha256};

pub type Map = serde_json::Map<String, Value>;

/// `JSON.stringify(value)`: insertion order, except that array-index keys come
/// first in ascending order, as ECMAScript objects enumerate them.
pub fn stringify(value: &Value) -> String {
    let mut out = String::new();
    write_value(&mut out, value, false);
    out
}

/// Canonical encoding: keys sorted by Unicode scalar (UTF-8 byte) order.
pub fn stable_stringify(value: &Value) -> String {
    let mut out = String::new();
    write_value(&mut out, value, true);
    out
}

/// Lowercase hex SHA-256 of the canonical encoding.
pub fn canonical_sha256(value: &Value) -> String {
    sha256_hex(stable_stringify(value).as_bytes())
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut hex = String::with_capacity(64);
    for byte in digest {
        hex.push(char::from_digit(u32::from(byte >> 4), 16).unwrap_or('0'));
        hex.push(char::from_digit(u32::from(byte & 15), 16).unwrap_or('0'));
    }
    hex
}

/// Structural equality ignoring object key order; numbers compare by value.
pub fn deep_equal(left: &Value, right: &Value) -> bool {
    stable_stringify(left) == stable_stringify(right)
}

fn write_value(out: &mut String, value: &Value, sorted: bool) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Number(number) => out.push_str(&number_string(number)),
        Value::String(text) => write_string(out, text),
        Value::Array(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                write_value(out, item, sorted);
            }
            out.push(']');
        }
        Value::Object(map) => {
            out.push('{');
            let entries = if sorted { sorted_entries(map) } else { ordered_entries(map) };
            for (index, (key, item)) in entries.into_iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                write_string(out, key);
                out.push(':');
                write_value(out, item, sorted);
            }
            out.push('}');
        }
    }
}

fn sorted_entries(map: &Map) -> Vec<(&String, &Value)> {
    let mut entries: Vec<_> = map.iter().collect();
    entries.sort_by(|left, right| left.0.cmp(right.0));
    entries
}

/// ECMAScript own-property order: integer indices ascending, then insertion.
pub fn ordered_entries(map: &Map) -> Vec<(&String, &Value)> {
    if !map.keys().any(|key| array_index(key).is_some()) {
        return map.iter().collect();
    }
    let mut indices: Vec<_> = map.iter().filter_map(|(k, v)| array_index(k).map(|i| (i, k, v))).collect();
    indices.sort_by_key(|entry| entry.0);
    let mut entries: Vec<_> = indices.into_iter().map(|(_, k, v)| (k, v)).collect();
    entries.extend(map.iter().filter(|(key, _)| array_index(key).is_none()));
    entries
}

fn array_index(key: &str) -> Option<u64> {
    if key.is_empty() || (key.len() > 1 && key.starts_with('0')) || !key.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    key.parse::<u64>().ok().filter(|value| *value < 4_294_967_295)
}

fn write_string(out: &mut String, text: &str) {
    out.push('"');
    for character in text.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            control if (control as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", control as u32));
            }
            other => out.push(other),
        }
    }
    out.push('"');
}

/// `String(number)` for a JSON number, which JavaScript holds as a double.
pub fn number_string(number: &Number) -> String {
    match number.as_f64() {
        Some(value) => float_string(value),
        None => number.to_string(),
    }
}

pub fn float_string(value: f64) -> String {
    if value == 0.0 {
        return "0".to_owned();
    }
    let mut buffer = ryu_js::Buffer::new();
    buffer.format(value).to_owned()
}

pub fn as_f64(value: &Value) -> Option<f64> {
    value.as_f64()
}

/// `Number.isInteger`.
pub fn is_integer(value: &Value) -> bool {
    value.as_f64().is_some_and(|n| n.is_finite() && n.fract() == 0.0)
}

/// `Number.isSafeInteger`.
pub fn is_safe_integer(value: &Value) -> bool {
    value.as_f64().is_some_and(|n| n.is_finite() && n.fract() == 0.0 && n.abs() <= 9_007_199_254_740_991.0)
}

/// `typeof value === "number" && Number.isFinite(value)`.
pub fn is_finite_number(value: &Value) -> bool {
    value.as_f64().is_some_and(f64::is_finite)
}

/// ECMAScript `WhiteSpace` and `LineTerminator`, the set `trim()` and `\s` use.
pub fn is_js_space(character: char) -> bool {
    matches!(
        character,
        '\t' | '\n' | '\u{b}' | '\u{c}' | '\r' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}' | '\u{feff}'
    )
}

pub fn js_trim(text: &str) -> &str {
    text.trim_matches(is_js_space)
}

/// The fixed RelayMark whitespace set from the specification.
pub fn is_relay_space(character: char) -> bool {
    matches!(
        character,
        '\u{9}'..='\u{d}' | ' ' | '\u{85}' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200a}' | '\u{2028}'
            | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}'
    )
}

/// A RelayMark non-empty string: at least one scalar outside the fixed set.
pub fn nonempty(value: &Value) -> bool {
    value.as_str().is_some_and(|text| text.chars().any(|c| !is_relay_space(c)))
}

pub fn trim_relay(text: &str) -> &str {
    text.trim_matches(is_relay_space)
}

/// JavaScript `string.length`: UTF-16 code units.
pub fn utf16_len(text: &str) -> usize {
    text.chars().map(char::len_utf16).sum()
}

pub fn object(value: &Value) -> Option<&Map> {
    value.as_object()
}

/// `value?.[key]` treating absent and non-object parents alike.
pub fn field<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    value.as_object().and_then(|map| map.get(key))
}

pub fn str_field<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    field(value, key).and_then(Value::as_str)
}

/// JavaScript truthiness of a JSON value.
pub fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(flag)) => *flag,
        Some(Value::Number(number)) => number.as_f64().is_some_and(|n| n != 0.0 && !n.is_nan()),
        Some(Value::String(text)) => !text.is_empty(),
        Some(_) => true,
    }
}

/// `value == null` for a possibly absent field.
pub fn is_nullish(value: Option<&Value>) -> bool {
    matches!(value, None | Some(Value::Null))
}

/// Parse authored JSON text. The reference runtime decodes with `JSON.parse`.
pub fn parse(text: &str) -> crate::Result<Value> {
    serde_json::from_str(text).map_err(|error| crate::Error::new(format!("Invalid JSON: {error}")))
}

/// Validate portable JSON depth. serde values are already finite and acyclic.
pub fn depth_within(value: &Value, limit: usize) -> bool {
    fn visit(value: &Value, depth: usize, limit: usize) -> bool {
        if depth > limit {
            return false;
        }
        match value {
            Value::Array(items) => items.iter().all(|item| visit(item, depth + 1, limit)),
            Value::Object(map) => map.values().all(|item| visit(item, depth + 1, limit)),
            _ => true,
        }
    }
    visit(value, 0, limit)
}

/// `String.prototype.localeCompare` under the root/en ICU collation the
/// reference runtime uses: punctuation, symbols, digits, then letters compared
/// without case or accents first, then accents, then lowercase before uppercase.
pub fn locale_compare(left: &str, right: &str) -> std::cmp::Ordering {
    fn weights(text: &str) -> Vec<(u32, u32, u32)> {
        use unicode_normalization::UnicodeNormalization;
        const ORDER: &str = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz";
        let mut out = Vec::new();
        for character in text.chars() {
            let mut decomposed = character.to_string().nfd().collect::<Vec<_>>().into_iter();
            let base = decomposed.next().unwrap_or(character);
            let accents: u32 = decomposed.map(|c| c as u32).sum();
            let lower = base.to_lowercase().next().unwrap_or(base);
            let primary = match ORDER.find(lower) {
                Some(index) if lower.is_ascii() => index as u32,
                _ => 0x100 + lower as u32,
            };
            let tertiary = u32::from(base != lower);
            out.push((primary, accents, tertiary));
        }
        out
    }
    let (a, b) = (weights(left), weights(right));
    let primary = a.iter().map(|w| w.0).cmp(b.iter().map(|w| w.0));
    let secondary = || a.iter().map(|w| w.1).cmp(b.iter().map(|w| w.1));
    let tertiary = || a.iter().map(|w| w.2).cmp(b.iter().map(|w| w.2));
    primary.then_with(secondary).then_with(tertiary)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn numbers_and_keys_follow_ecmascript() {
        let value: Value = serde_json::from_str(r#"{"b":1.0,"2":0.1,"a":1e21,"10":-0.0000001,"c":5e-7}"#).unwrap();
        assert_eq!(stringify(&value), r#"{"2":0.1,"10":-1e-7,"b":1,"a":1e+21,"c":5e-7}"#);
        assert_eq!(stringify(&json!("\u{1}\u{2028}é\"")), "\"\\u0001\u{2028}é\\\"\"");
    }

    #[test]
    fn locale_order_matches_icu_root() {
        let mut keys = vec!["a_b", "a1", "ab", "aB", "Ab", "a-b", "a.b", "a b", "A", "a", "_a", "1a", "a~", "a$", "$a", "z", "Z", "é", "e", "f"];
        keys.sort_by(|a, b| locale_compare(a, b));
        assert_eq!(keys, ["_a", "$a", "1a", "a", "A", "a b", "a_b", "a-b", "a.b", "a~", "a$", "a1", "ab", "aB", "Ab", "e", "é", "f", "z", "Z"]);
    }
}
