# Implementation Plan - STDF to XML Translator Service

## Goal Description
Create a robust, efficient, and best-practice STDF (Standard Test Data Format) to XML translator using Rust. The system will be designed as a microservice callable by a frontend.

## User Review Required
> [!IMPORTANT]
> **Streaming Architecture**: To handle potentially large STDF files (which can be gigabytes in size) without exhausting memory, I will implement a **streaming** architecture. The service will read chunks of the uploaded STDF file, parse records on the fly, and stream the generated XML back to the client immediately. This means we will not hold the entire file or the entire XML tree in memory.

## Proposed Changes

### Architecture
- **Language**: Rust.
- **Web Framework**: Axum.
- **Parser**: `rust-stdf` (Note: I will remove the `zip` feature to avoid unsafe code unless necessary, prioritizing standard reading).
- **XML Generation**: `quick-xml` with `Serializer`.

### Directory Structure
`stdf_translator/`
  - `Cargo.toml`
  - `src/`
    - `main.rs` (Web server entry point)
    - `translator.rs` (Core streaming logic)
    - `models.rs` (XML Data structures)

### Components

#### 1. Data Models (`src/models.rs`)
Based on the provided CSV `STDF_XML_DataElementMap.xls` (converted to CSV), we will define struct representations for XML serialization.
- `Lot` (from MIR, MRR)
- `Wafer` (from WIR, WRR)
- `Unit` (from PIR, PRR)
- `Meas` (from PTR, MPR, FTR)
- `Test` (from TSR)
- `Bin` (from HBR, SBR)
- `Audit` (from ATR)
- `File` (from FAR)

#### 2. Core Logic (`src/translator.rs`)
- **Streaming Loop**: Iterate `rust_stdf::Reader`.
- **State Machine**: Track current context to emit XML structure.
  - **Hierarchy**:
    ```xml
    <STDF>
      <File .../>
      <Lot ...>
        <Audit .../>
        <Wafer ...>
           <Unit ...>
              <Meas .../>
           </Unit>
        </Wafer>
      </Lot>
    </STDF>
    ```
  - The translator will maintain a stack of open XML tags to ensure proper nesting/closing as STDF records start/end (e.g., `WIR` starts Wafer, `WRR` ends it).

#### 3. Web Service (`src/main.rs`)
- **Endpoint**: `POST /convert`
- **Input**: Multipart form data (file upload) or raw body.
- **Output**: Streamed HTTP response (Content-Type: `application/xml`).

### Streaming Architecture (Added in v2)
To handle >1GB files without memory exhaustion:
1.  **Input Pipe**: Custom `ChannelReader` bridges Async Multipart Stream -> Sync `Read` for `rust-stdf`.
2.  **Processing**: `process_stdf_stream` runs in a dedicated blocking thread to avoid blocking the async runtime.
3.  **Output Pipe**: Custom `ChannelWriter` bridges Sync `Write` -> Async Stream for `Axum` response.
4.  **Backpressure**: Bounded channels (size 16 chunks) prevent memory buffering growth.

## Verification Plan

### Automated Tests
- **Unit Tests**: Test `process_stdf_stream` with small buffer-backed inputs.
- **Integration Tests**: Spin up the Axum server and hit it with a mock client.

### Manual Verification
- Run the service locally.
- Use `curl` to upload a dummy STDF file and inspect the XML output.
