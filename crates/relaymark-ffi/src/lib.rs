//! relaymark-core for Swift through uniffi: one call, the shared job table
//! (`relaymark_core::jobs`), with bytes in and out. The Swift package wraps it
//! in its typed codecs.

uniffi::setup_scaffolding!();

/// A refused job; `message` is the engine's reason.
#[derive(Debug, uniffi::Error)]
pub enum RelayMarkError {
    /// The input is not valid for the job.
    Refused {
        /// The engine's reason.
        message: String,
    },
}

impl std::fmt::Display for RelayMarkError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let RelayMarkError::Refused { message } = self;
        f.write_str(message)
    }
}

impl std::error::Error for RelayMarkError {}

/// Runs a relaymark-core job: input bytes (source text or JSON) and options
/// (a JSON object, or empty), answered with the result bytes.
#[uniffi::export]
pub fn relaymark_run(
    job: String,
    input: Vec<u8>,
    options: Vec<u8>,
) -> Result<Vec<u8>, RelayMarkError> {
    relaymark_core::jobs::run(&job, &input, &options)
        .map_err(|message| RelayMarkError::Refused { message })
}
