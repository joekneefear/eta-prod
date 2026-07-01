### Basic Web UI
To make the tool user-friendly for non-technical users without adding complexity:
1.  **Embedded HTML**: We will embed a simple `index.html` string directly into the Rust binary.
2.  **Route**: `GET /` will serve this HTML instead of the plain text message.
3.  **Functionality**:
    - A simple drag-and-drop file upload area.
    - JavaScript to `POST` the file to `/convert`.
    - Client-side download trigger for the resulting XML.

This approach keeps the tool as a **single binary** (no separate frontend deployment needed).

### Changes to `src/main.rs`
- Update `root` handler to return `Html<String>`.
- Add the HTML content constant.
