//! One error type for every conversion. Messages follow the reference runtime's
//! wording so hosts can keep matching on the same reasons.

use std::fmt;

/// A refused conversion: the input is not a valid RelayMark value for the
/// requested job. Nothing is partially converted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    message: String,
}

impl Error {
    pub(crate) fn new(message: impl Into<String>) -> Self {
        Self { message: message.into() }
    }

    /// The reason the input was refused.
    pub fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for Error {}

/// Result of every fallible engine call.
pub type Result<T> = std::result::Result<T, Error>;

/// Early return with an [`Error`] carrying a formatted message.
macro_rules! bail {
    ($($arg:tt)*) => { return Err($crate::error::Error::new(format!($($arg)*))) };
}
pub(crate) use bail;
