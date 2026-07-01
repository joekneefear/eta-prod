# STDF Translator Service

A robust, efficient STDF to XML translator written in Rust.

## Prerequisites
- Rust (latest stable)
- Cargo

## Building
```bash
cargo build --release
```

## Usage

### CLI Mode
Convert a file directly from the command line:

```bash
# Output to file
cargo run --release -- --input sample.stdf --output output.xml

# Output to stdout
cargo run --release -- --input sample.stdf > output.xml
```

### Server Mode
Start the web server:

```bash
cargo run --release -- --server
```
The service will start on `http://127.0.0.1:3000`. 
**Open this URL in your browser to use the graphical upload interface.**

Or use the API endpoint:
```bash
curl -X POST -F "file=@/path/to/your/file.stdf" http://127.0.0.1:3000/convert > output.xml
```

### Large Uploads (Resumable)
The web UI now supports resumable chunked uploads for very large files. You can also upload via CLI and then load the upload ID in the browser.

#### CLI Uploader
```bash
# Upload to a proxy path (default)
cargo run --release --bin stdf_uploader -- --folder batch-20260213-053854 /path/to/large.stdf

# Upload direct to the Rust server
cargo run --release --bin stdf_uploader -- --base-url http://127.0.0.1:3000 --folder batch-20260213-053854 /path/to/large.stdf
```

In the browser UI, use "Load existing upload ID" to pull the batch and then run translation.

## Implementation Details
- **Streaming**: The core logic is designed to stream data. 
- **Structure**: Maps STDF records to XML elements as defined in the mapping specs.
- **Records Supported**: FAR, MIR, MRR, WIR, WRR, PIR, PRR, PTR, MPR, FTR.

## Project Structure
- `src/main.rs`: Entry point handling both CLI and Web Server modes.
- `src/translator.rs`: Streaming STDF reading and XML writing.
- `src/models.rs`: Data structures for XML serialization.

## Java Integration

You can easily use this tool from Java in two ways:

### 1. As a Command Line Interface (CLI) - **Recommended for Batch Processing**
Use `ProcessBuilder` to invoke the binary.

```java
ProcessBuilder pb = new ProcessBuilder(
    "path/to/stdf_translator", 
    "--input", "input.stdf", 
    "--output", "output.xml"
);
pb.inheritIO();
Process p = pb.start();
int exitCode = p.waitFor();
```

### 2. As a Web Service - **Recommended for Web Apps**
If you run the translator as a service (`--server`), you can call it using Java's `HttpClient`.

```java
HttpClient client = HttpClient.newHttpClient();
HttpRequest request = HttpRequest.newBuilder()
    .uri(URI.create("http://localhost:3000/convert"))
    .POST(HttpRequest.BodyPublishers.ofFile(Paths.get("sample.stdf")))
    .header("Content-Type", "multipart/form-data; boundary=...") // Use a multipart library like Apache HttpClient for easier handling
    .build();

HttpResponse<Path> response = client.send(request, HttpResponse.BodyHandlers.ofFile(Paths.get("output.xml")));
```

### 3. As a Native Library (JNI)
*Not recommended* due to complexity. CLI/HTTP is preferred for stability.
