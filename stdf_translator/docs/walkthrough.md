# STDF Translator Service Implementation Walkthrough

I have implemented a Rust-based STDF to XML translator service. Due to environment limitations, this code has been written without local compilation, but it follows Rust best practices and the provided mapping specifications.

## Changes Made

### 1. Data Models (`src/models.rs`)
Defines the XML schema as Rust structs using `serde`.
- Maps STDF records (`MIR`, `WIR`, `PIR`, `PTR`, etc.) to XML elements (`Lot`, `Wafer`, `Unit`, `Meas`).
- Attributes names match the CSV mapping provided.

### 2. Core Translator (`src/translator.rs`)
Implemented a streaming converter function `process_stdf_stream`.
- **Input**: Any `BufRead` source (file, network stream).
- **Output**: Writes XML events directly to the output stream.
- **Logic**: Iterates over STDF records and maintains a simple state machine (Lot -> Wafer -> Unit) to ensure valid XML nesting.

### 3. Web Service (`src/main.rs`)
Implemented an `axum` web server.
- **Endpoint**: `POST /convert`
- **Behavior**: Accepts multipart file uploads, processes them in memory (for simplicity and safety in this blind implementation), and returns the generated XML.

## Verification Steps (For User)

Since I cannot run the code here, please follow these steps to verify it on a machine with Rust installed:

1. **Copy the directory**: Move `stdf_translator` to your development machine.
2. **Build**: Run `cargo build --release`.
3. **Run**: 
   - **Server Mode**: `cargo run --release -- --server`
   - **CLI Mode**: `cargo run --release -- --input sample.stdf --output output.xml`
4. **Test**:
   - **CLI**: `cargo run --release -- --input sample.stdf --output output.xml`
   - **Web UI**: Open `http://localhost:3000`. Drag & drop an STDF file.
     - **Verify**: Check the "Processing Time" and "File Size" stats.
     - **Verify**: Explore the XML tree by clicking on the arrows to expand/collapse sections.
     - **Verify**: Click "Download File" to save the result.
   - **Web API**: `curl -X POST -F "file=@sample.stdf" http://localhost:3000/convert > output.xml`
5. **Validation**: Check if `output.xml` matches the structure defined in `STDF_XML_DataElementMap.xls`.

## Known Limitations / Future Improvements
- **Streaming Uploads**: Currently buffers the full file in memory. For optimal efficiency with large files (>1GB), this should be upgraded to use a streaming body reader piped directly to the translator.
- **Testing**: Requires real STDF files to fully validate the parsing logic.
