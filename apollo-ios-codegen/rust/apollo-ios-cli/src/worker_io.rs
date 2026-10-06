//! Length-delimited protobuf I/O for the Bazel worker protocol.
//!
//! Reads WorkRequest messages from stdin and writes WorkResponse
//! messages to stdout using varint length-delimited encoding.
//! All non-protocol output goes to stderr (WRKR-04, D-96).

use prost::Message;
use std::io::{self, Read, Write};

use crate::worker_proto::{WorkRequest, WorkResponse};

/// Reads a single length-delimited WorkRequest from the reader.
///
/// Returns `Ok(Some(request))` on success, `Ok(None)` on EOF
/// (stdin closed = graceful shutdown per D-95), or `Err` on
/// protocol errors.
///
/// The varint length prefix follows protobuf's standard encoding:
/// each byte's MSB indicates continuation (1=more bytes, 0=last).
pub fn read_work_request(reader: &mut impl Read) -> io::Result<Option<WorkRequest>> {
    // Read varint length prefix byte-by-byte
    let mut len_buf = Vec::new();
    loop {
        let mut byte = [0u8; 1];
        match reader.read_exact(&mut byte) {
            Ok(()) => {
                len_buf.push(byte[0]);
                // MSB=0 means this is the last byte of the varint
                if byte[0] & 0x80 == 0 {
                    break;
                }
                if len_buf.len() > 10 {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "varint length prefix exceeds 10 bytes",
                    ));
                }
            }
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => {
                if len_buf.is_empty() {
                    // EOF on the very first byte = clean shutdown
                    return Ok(None);
                }
                // EOF mid-varint = protocol error
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "unexpected EOF while reading varint length prefix",
                ));
            }
            Err(e) => return Err(e),
        }
    }

    let len = prost::decode_length_delimiter(&len_buf[..])
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    // Guard against oversized messages (64 MB max)
    const MAX_MESSAGE_SIZE: usize = 64 * 1024 * 1024;
    if len > MAX_MESSAGE_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("message size {} exceeds maximum {}", len, MAX_MESSAGE_SIZE),
        ));
    }

    // Read exactly `len` bytes of message data
    let mut msg_buf = vec![0u8; len];
    reader.read_exact(&mut msg_buf)?;

    WorkRequest::decode(&msg_buf[..])
        .map(Some)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

/// Writes a single length-delimited WorkResponse to the writer.
///
/// Only WorkResponse bytes appear on the writer (stdout).
/// All other output must go to stderr (WRKR-04, D-96).
pub fn write_work_response(writer: &mut impl Write, response: &WorkResponse) -> io::Result<()> {
    let encoded = response.encode_length_delimited_to_vec();
    writer.write_all(&encoded)?;
    writer.flush()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn test_round_trip_work_request() {
        // Encode a WorkRequest
        let request = WorkRequest {
            arguments: vec![
                "generate".to_string(),
                "--path".to_string(),
                "config.json".to_string(),
            ],
            inputs: vec![],
            request_id: 0,
            cancel: false,
            verbosity: 0,
            sandbox_dir: String::new(),
        };
        let encoded = request.encode_length_delimited_to_vec();

        // Read it back
        let mut cursor = Cursor::new(encoded);
        let decoded = read_work_request(&mut cursor).unwrap().unwrap();
        assert_eq!(decoded.arguments, request.arguments);
        assert_eq!(decoded.request_id, 0);
    }

    #[test]
    fn test_round_trip_work_response() {
        let response = WorkResponse {
            exit_code: 0,
            output: String::new(),
            request_id: 0,
            was_cancelled: false,
        };
        let mut buf = Vec::new();
        write_work_response(&mut buf, &response).unwrap();

        // Decode and verify
        let mut cursor = Cursor::new(buf);
        // Read as raw proto to verify encoding
        let decoded_response: WorkResponse = {
            let mut len_buf = Vec::new();
            loop {
                let mut byte = [0u8; 1];
                cursor.read_exact(&mut byte).unwrap();
                len_buf.push(byte[0]);
                if byte[0] & 0x80 == 0 {
                    break;
                }
            }
            let len = prost::decode_length_delimiter(&len_buf[..]).unwrap();
            let mut msg_buf = vec![0u8; len];
            cursor.read_exact(&mut msg_buf).unwrap();
            WorkResponse::decode(&msg_buf[..]).unwrap()
        };
        assert_eq!(decoded_response.exit_code, 0);
        assert_eq!(decoded_response.request_id, 0);
    }

    #[test]
    fn test_eof_returns_none() {
        let mut cursor = Cursor::new(Vec::<u8>::new());
        let result = read_work_request(&mut cursor).unwrap();
        assert!(result.is_none());
    }

    #[test]
    fn test_oversized_message_rejected() {
        // Create a varint encoding a size > 64MB
        let huge_size: u64 = 128 * 1024 * 1024;
        let mut len_encoded = Vec::new();
        prost::encode_length_delimiter(huge_size as usize, &mut len_encoded).unwrap();
        let mut cursor = Cursor::new(len_encoded);
        let result = read_work_request(&mut cursor);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.to_string().contains("exceeds maximum"));
    }

    #[test]
    fn test_request_with_inputs() {
        use crate::worker_proto::Input;
        let request = WorkRequest {
            arguments: vec!["generate".to_string()],
            inputs: vec![
                Input {
                    path: "schema.graphqls".to_string(),
                    digest: vec![1, 2, 3, 4],
                },
                Input {
                    path: "query.graphql".to_string(),
                    digest: vec![5, 6, 7, 8],
                },
            ],
            request_id: 0,
            cancel: false,
            verbosity: 0,
            sandbox_dir: String::new(),
        };
        let encoded = request.encode_length_delimited_to_vec();
        let mut cursor = Cursor::new(encoded);
        let decoded = read_work_request(&mut cursor).unwrap().unwrap();
        assert_eq!(decoded.inputs.len(), 2);
        assert_eq!(decoded.inputs[0].path, "schema.graphqls");
        assert_eq!(decoded.inputs[0].digest, vec![1, 2, 3, 4]);
    }
}
