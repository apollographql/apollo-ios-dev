fn main() -> std::io::Result<()> {
    let proto_file = "../proto/worker_protocol.proto";

    let file_descriptors = protox::compile([proto_file], ["../proto/"])
        .expect("Failed to compile worker_protocol.proto");

    prost_build::Config::new()
        .compile_fds(file_descriptors)
        .expect("Failed to generate Rust types from proto");

    println!("cargo::rerun-if-changed={}", proto_file);
    Ok(())
}
