//! The RelayMark engine as one Erlang NIF: a job name, its input bytes and its
//! options as JSON, answered with `{:ok, binary}` or `{:error, reason}`.
//! `run` stays on a normal scheduler for small inputs; `run_dirty` takes the
//! same call on a dirty CPU scheduler, which the Elixir side picks by size.

use relaymark_core::jobs;
use rustler::{Atom, Binary, Encoder, Env, OwnedBinary, Term};

mod atoms {
    rustler::atoms! { ok, error }
}

#[rustler::nif]
fn run<'a>(env: Env<'a>, job: &str, input: Binary, options: Binary) -> Term<'a> {
    answer(env, job, input.as_slice(), options.as_slice())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_dirty<'a>(env: Env<'a>, job: &str, input: Binary, options: Binary) -> Term<'a> {
    answer(env, job, input.as_slice(), options.as_slice())
}

fn answer<'a>(env: Env<'a>, job: &str, input: &[u8], options: &[u8]) -> Term<'a> {
    let (tag, bytes): (Atom, Vec<u8>) = match jobs::run(job, input, options) {
        Ok(bytes) => (atoms::ok(), bytes),
        Err(reason) => (atoms::error(), reason.into_bytes()),
    };
    let mut binary = OwnedBinary::new(bytes.len()).expect("allocate result binary");
    binary.as_mut_slice().copy_from_slice(&bytes);
    (tag, binary.release(env)).encode(env)
}

rustler::init!("Elixir.RelayMark.Native");
