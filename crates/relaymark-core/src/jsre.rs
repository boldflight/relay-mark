//! Regular expressions written with ECMAScript meaning. The rules are ported
//! from the reference runtime, whose `\s`, `\d`, `\w` and `.` differ from the
//! `regex` crate's Unicode defaults; patterns are translated once at first use.

use regex::Regex;

const JS_SPACE: &str = r"\t\n\x0B\x0C\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}";

/// Translate an ECMAScript pattern (with the `u` flag) to `regex` syntax.
pub fn translate(pattern: &str) -> String {
    let mut out = String::with_capacity(pattern.len() * 2);
    let mut chars = pattern.chars();
    let mut in_class = false;
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                let Some(next) = chars.next() else { break };
                match next {
                    's' if in_class => out.push_str(JS_SPACE),
                    's' => out.push_str(&format!("[{JS_SPACE}]")),
                    'S' => out.push_str(&format!("[^{JS_SPACE}]")),
                    'd' if in_class => out.push_str("0-9"),
                    'd' => out.push_str("[0-9]"),
                    'w' if in_class => out.push_str("A-Za-z0-9_"),
                    'w' => out.push_str("[A-Za-z0-9_]"),
                    'u' => {
                        // \u{...} with the u flag, or \uXXXX.
                        let rest: String = chars.clone().take(6).collect();
                        if rest.starts_with('{') {
                            let hex: String = chars.by_ref().skip(1).take_while(|c| *c != '}').collect();
                            out.push_str(&format!("\\x{{{hex}}}"));
                        } else {
                            let hex: String = chars.by_ref().take(4).collect();
                            out.push_str(&format!("\\x{{{hex}}}"));
                        }
                    }
                    other => {
                        out.push('\\');
                        out.push(other);
                    }
                }
            }
            '[' if !in_class => {
                in_class = true;
                out.push('[');
                if chars.clone().next() == Some('^') {
                    out.push('^');
                    chars.next();
                }
                // A literal `]` or `[` first in a JS class is still a member.
                if chars.clone().next() == Some(']') {
                    out.push_str("\\]");
                    chars.next();
                }
            }
            '[' => out.push_str("\\["),
            ']' if in_class => {
                in_class = false;
                out.push(']');
            }
            '.' if !in_class => out.push_str(r"[^\n\r\x{2028}\x{2029}]"),
            '&' | '~' if in_class => {
                out.push('\\');
                out.push(c);
            }
            other => out.push(other),
        }
    }
    out
}

pub fn compile(pattern: &str) -> Regex {
    let translated = translate(pattern);
    Regex::new(&translated).unwrap_or_else(|error| panic!("pattern {pattern} → {translated}: {error}"))
}

/// A lazily compiled ECMAScript regular expression.
macro_rules! js_regex {
    ($pattern:expr) => {{
        static CELL: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
        CELL.get_or_init(|| $crate::jsre::compile($pattern))
    }};
}
pub(crate) use js_regex;

#[cfg(test)]
mod tests {
    #[test]
    fn javascript_classes_keep_their_meaning() {
        let space = super::compile(r"^\s+$");
        assert!(space.is_match("\u{feff}\u{a0}"));
        assert!(!space.is_match("\u{85}"));
        assert!(!super::compile(r"^\d$").is_match("٣"));
        assert!(!super::compile(r"^.$").is_match("\u{2028}"));
        assert!(super::compile(r"^[\s\S]+$").is_match("a\nb"));
        assert!(super::compile(r"^[^\]]+$").is_match("ab"));
    }
}
