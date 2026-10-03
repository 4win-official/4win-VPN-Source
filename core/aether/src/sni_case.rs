//! mixed-case SNI, after L×Box spec 028.
//!
//! ## What this does
//!
//! Many regional DPI engines match the `server_name` field of the TLS
//! ClientHello by exact string, because normalising case on every packet is
//! expensive on cheap hardware in front of a big pipe. RFC 6066 §3 and RFC
//! 1035 §2.3.3 both say the hostname is case-insensitive, so a server is
//! obliged to accept any casing. Writing the same name with random casing
//! therefore reaches the server unmodified and defeats a plain exact match.
//!
//! ## Why this is safe here specifically
//!
//! Cloudflare terminates the MASQUE tunnel and resolves the ClientHello SNI
//! case-insensitively — verified against the real endpoint, the handshake
//! completes and the tunnel carries traffic. So the change cannot break the
//! tunnel: either the casing is ignored, or, on the far end of a path where
//! some middlebox normalises case, it simply matches as it always did.
//!
//! ## What it does NOT do
//!
//! It is not domain fronting and not a REALITY/uTLS replacement. It does not
//! hide the SNI from anyone who normalises case before matching, and it says
//! nothing about the GFW-class filters that do. It is one cheap extra layer
//! that is free to combine with TLS fragmentation, which is the other
//! anti-DPI measure this core already has.
//!
//! ## Determinism
//!
//! The casing is chosen per connection, not per session, and never persisted.
//! A censor that records a connection and replays it sees a different casing
//! on the next one, but a censor that classifies in real time is the one this
//! aims at. The DNS name that the client resolves is untouched — only the
//! bytes on the wire in the ClientHello change.
//!
//! ## Scope
//!
//! Applied to the SNI we already send, never to a hostname we have not
//! verified. [mix] is therefore called at the points that build the MASQUE
//! SNI from [crate::consts::CONNECT_SNI], and nowhere else.

use std::env;

/// The environment override, so a field toggle does not require a rebuild.
///
/// Reads `AETHER_MIXED_CASE_SNI`: `1`/`on`/`yes`/`true` (any case) enables,
/// `0`/`off`/`no`/`false` disables, and anything else (including unset)
/// leaves the feature off. Unset means off because the existing behaviour
/// is already correct for every network that is not doing exact-match SNI,
/// and a change to the bytes on the wire has to be opt-in.
fn enabled() -> bool {
    match env::var("AETHER_MIXED_CASE_SNI") {
        Ok(raw) => match raw.trim().to_lowercase().as_str() {
            "1" | "on" | "yes" | "true" => true,
            "0" | "off" | "no" | "false" => false,
            // An unrecognised value is not a silent enable.
            _ => false,
        },
        Err(_) => false,
    }
}

/// True when the caller should keep the exact casing it already has.
///
/// Exposed so a probe or a health check can report the mode, and so the config
/// builder can say in the log what it is about to send.
pub fn is_enabled() -> bool {
    enabled()
}

/// Randomise the casing of `name` without changing any other byte.
///
/// Letters flip with probability ~1/2, so a name is never left unchanged by
/// accident on a long name and is never turned into something unrecognisable
/// — the set of characters is identical, only their case varies. Digits,
/// dots, hyphens and underscores are untouched by construction, so a valid
/// hostname cannot be made invalid.
///
/// Returns the input unchanged when the feature is off, which is the whole
/// point of funnelling every SNI through here: no call site has to branch.
pub fn mix(name: &str) -> String {
    if !enabled() || name.is_empty() {
        return name.to_string();
    }

    // Rejection sampling is not needed: the domain of the transform is ASCII
    // letters only, and every other byte is copied verbatim.
    let mut out = String::with_capacity(name.len());
    for byte in name.bytes() {
        match byte {
            b'a'..=b'z' => {
                // A coin flip per letter. rand is already a dependency of this
                // crate; cheap here because a name is at most 253 bytes.
                if rand::random() {
                    out.push(byte.to_ascii_uppercase() as char);
                } else {
                    out.push(byte as char);
                }
            }
            b'A'..=b'Z' => {
                if rand::random() {
                    out.push(byte.to_ascii_lowercase() as char);
                } else {
                    out.push(byte as char);
                }
            }
            _ => out.push(byte as char),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The feature off: the name must pass through byte-identical. This is
    /// the guarantee every call site relies on to need no branch of its own.
    #[test]
    fn off_is_a_passthrough() {
        std::env::remove_var("AETHER_MIXED_CASE_SNI");
        assert_eq!(
            mix("consumer-masque.cloudflareclient.com"),
            "consumer-masque.cloudflareclient.com"
        );
        assert_eq!(mix(""), "");
    }

    /// On: the name must still be the same name, case-insensitively. Nothing
    /// else may change — no dropped bytes, no new bytes, no moved dots.
    #[test]
    fn on_preserves_the_name_case_insensitively() {
        std::env::set_var("AETHER_MIXED_CASE_SNI", "on");
        let original = "consumer-masque.cloudflareclient.com";
        let mixed = mix(original);
        assert_eq!(mixed.len(), original.len());
        assert_eq!(mixed.to_lowercase(), original.to_lowercase());
        // Dots survive exactly.
        assert_eq!(mixed.matches('.').count(), original.matches('.').count());
        std::env::remove_var("AETHER_MIXED_CASE_SNI");
    }

    /// An unrecognised value must not enable the feature.
    #[test]
    fn an_unrecognised_value_is_off() {
        std::env::set_var("AETHER_MIXED_CASE_SNI", "maybe");
        assert_eq!(mix("example.com"), "example.com");
        std::env::remove_var("AETHER_MIXED_CASE_SNI");
    }

    /// A name that is already mixed must round-trip to a still-valid name.
    #[test]
    fn handles_uppercase_input() {
        std::env::set_var("AETHER_MIXED_CASE_SNI", "1");
        let mixed = mix("EXAMPLE.COM");
        assert_eq!(mixed.to_lowercase(), "example.com");
        std::env::remove_var("AETHER_MIXED_CASE_SNI");
    }
}
