use axum::{
    body::Body,
    extract::{DefaultBodyLimit, Multipart, Query, Path as AxumPath},
    http::StatusCode,
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use bytes::Bytes;
use clap::Parser;
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::convert::Infallible;
use std::fs::File;
use std::io::{BufWriter, SeekFrom};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncSeekExt, AsyncWriteExt};
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod models;
mod translator;
mod text_translator;
mod stream_utils;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Start the web server
    #[arg(short, long)]
    server: bool,

    /// Input STDF file for CLI mode
    #[arg(short, long)]
    input: Option<String>,

    /// Output file for CLI mode
    #[arg(short, long)]
    output: Option<String>,

    /// Output format: xml or text
    #[arg(short, long, default_value = "xml")]
    format: String,
}

const UPLOAD_ROOT: &str = "/apps/exensio_data/data/rustdf/uploads";
const OUTPUT_ROOT: &str = "/apps/exensio_data/data/rustdf/outputs";
const LOG_ROOT: &str = "/apps/exensio_data/data/rustdf/logs";
const MAX_BODY_BYTES: usize = 10 * 1024 * 1024 * 1024; // 10 GB
const UPLOAD_BUFFER_BYTES: usize = 32 * 1024 * 1024; // 32 MB
const CHUNK_DIR_NAME: &str = ".chunks";

#[derive(Serialize)]
struct UploadFileInfo {
    name: String,
    size_bytes: u64,
}

#[derive(Serialize)]
struct UploadResponse {
    upload_id: String,
    upload_folder: String,
    files: Vec<UploadFileInfo>,
}

#[derive(Deserialize)]
struct UploadInitRequest {
    folder: Option<String>,
    allow_existing: Option<bool>,
}

#[derive(Serialize)]
struct UploadInitResponse {
    upload_id: String,
    upload_folder: String,
}

#[derive(Deserialize)]
struct TranslateRequest {
    upload_id: String,
    output_folder: String,
    format: Option<String>,
}

#[derive(Deserialize)]
struct UploadListQuery {
    upload_id: String,
}

#[derive(Serialize)]
struct UploadListResponse {
    upload_id: String,
    files: Vec<UploadFileInfo>,
}

#[derive(Deserialize)]
struct ChunkUploadQuery {
    upload_id: String,
    file_name: String,
    chunk_index: u32,
    total_chunks: u32,
    chunk_size: u64,
    total_size: u64,
}

#[derive(Deserialize)]
struct UploadStatusQuery {
    upload_id: String,
    file_name: String,
}

#[derive(Serialize, Deserialize)]
struct ChunkState {
    total_chunks: u32,
    total_size: u64,
    chunk_size: u64,
    received: Vec<u8>,
}

#[derive(Serialize)]
struct ChunkUploadResponse {
    upload_id: String,
    file: UploadFileInfo,
    complete: bool,
    received_chunks: u32,
    total_chunks: u32,
}

#[derive(Serialize)]
struct UploadStatusResponse {
    upload_id: String,
    file: String,
    total_chunks: u32,
    received_chunks: Vec<u32>,
    completed: bool,
}

const INDEX_HTML: &str = r#"
<!DOCTYPE html>
<html lang="en">
</script>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>STDF Translator Benchmarks</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/styles/default.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/highlight.min.js"></script>
    <style>
        :root {
            --ink: #0d1b1e;
            --ink-muted: #475056;
            --accent: #ff6b35;
            --accent-2: #1b998b;
            --surface: #f7f5f0;
            --panel: #ffffff;
            --stroke: rgba(13, 27, 30, 0.15);
            --glow: rgba(255, 107, 53, 0.25);
            --shadow: 0 18px 40px rgba(13, 27, 30, 0.12);
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            font-family: "Space Grotesk", sans-serif;
            color: var(--ink);
            background: radial-gradient(circle at top left, #fff3e7 0%, #f7f5f0 40%, #f0f4f6 100%);
            min-height: 100vh;
        }

        body::before {
            content: "";
            position: fixed;
            inset: 0;
            background: repeating-linear-gradient(115deg, rgba(13, 27, 30, 0.03) 0 1px, transparent 1px 12px);
            pointer-events: none;
            opacity: 0.4;
        }

        header {
            padding: 14px 6vw 12px;
            position: relative;
        }

        header h1 {
            margin: 0;
            font-size: clamp(1.2rem, 2.2vw, 1.6rem);
            letter-spacing: -0.01em;
            font-weight: 600;
        }

        header p {
            margin-top: 6px;
            max-width: 560px;
            color: var(--ink-muted);
            font-size: 0.95rem;
        }

        .shell {
            display: grid;
            gap: 24px;
            grid-template-columns: minmax(240px, 1fr) minmax(0, 2.6fr);
            padding: 0 6vw 56px;
        }

        .panel {
            background: var(--panel);
            border: 1px solid var(--stroke);
            border-radius: 18px;
            box-shadow: var(--shadow);
            padding: 22px;
            position: relative;
            overflow: hidden;
        }

        .panel::after {
            content: "";
            position: absolute;
            right: -40px;
            top: -40px;
            width: 120px;
            height: 120px;
            background: radial-gradient(circle, var(--glow), transparent 70%);
            opacity: 0.6;
        }

        .stage-card {
            display: grid;
            gap: 16px;
        }

        .stage {
            border: 1px dashed var(--stroke);
            border-radius: 14px;
            padding: 14px 16px;
            background: #faf7f2;
        }

        .stage h3 {
            margin: 0;
            font-size: 1rem;
        }

        .stage p {
            margin: 6px 0 0;
            color: var(--ink-muted);
            font-size: 0.9rem;
        }

        .stack {
            display: grid;
            gap: 18px;
        }

        .section-title {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 6px;
        }

        .section-title h2 {
            margin: 0;
            font-size: 1.3rem;
        }

        .pill {
            font-size: 0.8rem;
            padding: 4px 10px;
            border-radius: 999px;
            background: rgba(27, 153, 139, 0.12);
            color: var(--accent-2);
        }

        .grid-2 {
            display: grid;
            gap: 16px;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        }

        label {
            display: block;
            font-size: 0.85rem;
            margin-bottom: 6px;
            color: var(--ink-muted);
        }

        input[type="text"],
        select {
            width: 100%;
            padding: 10px 12px;
            border-radius: 10px;
            border: 1px solid var(--stroke);
            font-family: "Space Grotesk", sans-serif;
        }

        .drop-zone {
            border: 2px dashed var(--accent);
            border-radius: 16px;
            padding: 26px;
            text-align: center;
            background: #fff7f0;
            transition: transform 0.2s ease, background 0.2s ease;
        }

        .drop-zone.dragover {
            transform: translateY(-2px);
            background: #fff0e5;
        }

        .file-input { display: none; }

        .btn {
            appearance: none;
            border: none;
            padding: 12px 18px;
            border-radius: 10px;
            font-weight: 600;
            cursor: pointer;
            background: var(--accent);
            color: #fff;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
            box-shadow: 0 12px 24px rgba(255, 107, 53, 0.25);
        }

        .btn.secondary {
            background: var(--accent-2);
            box-shadow: 0 12px 24px rgba(27, 153, 139, 0.25);
        }

        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            box-shadow: none;
        }

        .btn:hover:not(:disabled) { transform: translateY(-1px); }

        .file-list {
            margin: 14px 0 0;
            display: grid;
            gap: 8px;
            font-family: "IBM Plex Mono", monospace;
            font-size: 0.85rem;
        }

        .file-item {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 10px;
            border-radius: 8px;
            background: #f4f3ef;
            border: 1px solid var(--stroke);
            flex-wrap: wrap;
        }

        .file-item .file-name {
            flex: 1 1 auto;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .file-item .file-size {
            flex: 0 0 auto;
            color: var(--ink-muted);
        }

        .inline-label {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 0.9rem;
            color: var(--ink-muted);
        }

        .progress-track {
            width: 100%;
            height: 6px;
            background: rgba(13, 27, 30, 0.08);
            border-radius: 999px;
            overflow: hidden;
            margin-top: 6px;
        }

        .progress-bar {
            height: 100%;
            width: 0%;
            background: var(--accent-2);
            transition: width 0.2s ease;
        }

        .status-line {
            margin-top: 10px;
            font-size: 0.9rem;
            color: var(--ink-muted);
        }

        .spinner {
            width: 36px;
            height: 36px;
            border-radius: 50%;
            border: 4px solid rgba(13, 27, 30, 0.12);
            border-top-color: var(--accent);
            animation: spin 0.8s linear infinite;
            display: none;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.85rem;
        }

        thead th {
            text-align: left;
            padding: 10px 8px;
            border-bottom: 1px solid var(--stroke);
        }

        tbody td {
            padding: 10px 8px;
            border-bottom: 1px solid rgba(13, 27, 30, 0.08);
        }

        .badge {
            padding: 3px 8px;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 600;
            background: rgba(255, 107, 53, 0.15);
            color: var(--accent);
        }

        .badge.done {
            background: rgba(27, 153, 139, 0.15);
            color: var(--accent-2);
        }

        .badge.error {
            background: rgba(208, 66, 48, 0.15);
            color: #d04230;
        }

        .mono { font-family: "IBM Plex Mono", monospace; }

        .file-cell {
            max-width: clamp(160px, 35vw, 360px);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .output-cell {
            max-width: clamp(160px, 30vw, 320px);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .reveal { animation: rise 0.6s ease forwards; opacity: 0; transform: translateY(10px); }
        .reveal.delay-1 { animation-delay: 0.1s; }
        .reveal.delay-2 { animation-delay: 0.2s; }
        .reveal.delay-3 { animation-delay: 0.3s; }

        @keyframes rise {
            to { opacity: 1; transform: translateY(0); }
        }

        @media (max-width: 900px) {
            .shell { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <header>
        <h1>STDF Translator Benchmarking</h1>
        <p>Upload files to the server first, then trigger translation with per-file benchmarks from start to output generation.</p>
    </header>

    <main class="shell">
        <section class="panel stage-card reveal">
            <div class="stage">
                <h3>1. Upload</h3>
                <p>Files are stored in a server folder before translation begins.</p>
            </div>
            <div class="stage">
                <h3>2. Translate</h3>
                <p>Pick an output folder and format, then run translation.</p>
            </div>
            <div class="stage">
                <h3>3. Benchmark</h3>
                <p>Each file reports start time, end time, duration, and output size.</p>
            </div>
        </section>

        <section class="stack">
            <div style="display:flex; gap:12px; align-items:center;">
                <label style="font-size:0.95rem; color:var(--ink-muted);">Outputs folder:</label>
                <input id="outputs-folder-input" type="text" placeholder="enter output folder" style="padding:8px 10px; border-radius:8px; border:1px solid var(--stroke);">
                <button class="btn secondary" id="list-outputs-btn" type="button">List outputs</button>
                <button class="btn" id="list-folders-btn" type="button">List folders</button>
            </div>
            <section class="panel reveal delay-1">
                <div class="section-title">
                    <h2>Upload to Server</h2>
                    <span class="pill" id="upload-folder-pill">No folder yet</span>
                </div>
                <div class="grid-2">
                    <div>
                        <label for="upload-folder">Upload folder name</label>
                        <input id="upload-folder" type="text" placeholder="batch-20260212-120000">
                    </div>
                    <div>
                        <label>Output format</label>
                        <select id="format-select">
                            <option value="xml">XML</option>
                            <option value="text">Text</option>
                        </select>
                    </div>
                </div>

                <div class="drop-zone" id="drop-zone">
                    <p>Drag and drop STDF files here (.stdf, .std, .zip, .gz). Zip/Gzip entries without extensions are accepted.</p>
                    <button class="btn" id="browse-btn" type="button">Browse Files</button>
                    <input class="file-input" id="file-input" type="file" accept=".stdf,.std,.zip,.gz" multiple>
                    <div class="file-list" id="file-list"></div>
                </div>

                <div style="margin-top: 12px;">
                    <label class="inline-label">
                        <input type="checkbox" id="resumable-toggle" checked>
                        Use resumable uploads (recommended for large files)
                    </label>
                </div>

                <div class="grid-2" style="margin-top: 12px;">
                    <div>
                        <label for="existing-upload-id">Load existing upload ID</label>
                        <input id="existing-upload-id" type="text" placeholder="batch-20260212-120000">
                    </div>
                    <div>
                        <label for="load-batch-btn">Action</label>
                        <button class="btn secondary" id="load-batch-btn" type="button">Load Batch</button>
                    </div>
                </div>
                <div class="status-line" id="load-status">Use this to access uploads from CLI or previous sessions.</div>

                <div style="margin-top: 16px; display: flex; gap: 12px; align-items: center;">
                    <button class="btn" id="upload-btn" type="button">Upload to Server</button>
                    <div class="spinner" id="upload-spinner" aria-hidden="true"></div>
                    <span class="status-line" id="upload-status">Waiting for files.</span>
                </div>
            </section>

            <section class="panel reveal delay-2">
                <div class="section-title">
                    <h2>Translate</h2>
                    <span class="pill" id="output-folder-pill">No output folder</span>
                </div>
                <div class="grid-2">
                    <div>
                        <label for="output-folder">Output folder</label>
                        <input id="output-folder" type="text" placeholder="output-20260212-120000">
                    </div>
                    <div>
                        <label for="translate-btn">Action</label>
                        <button class="btn secondary" id="translate-btn" type="button" disabled>Translate and Benchmark</button>
                    </div>
                </div>
                <div class="status-line" id="translate-status">Upload files to enable translation.</div>
            </section>

            <section class="panel reveal delay-3">
                <div class="section-title">
                    <h2>Benchmark Timeline</h2>
                    <span class="pill" id="batch-status">Idle</span>
                </div>
                <div style="overflow-x: auto;">
                    <table>
                        <thead>
                            <tr>
                                <th>File</th>
                                <th>Size</th>
                                <th>Start</th>
                                <th>End</th>
                                <th>Duration</th>
                                <th>Output</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody id="bench-table"></tbody>
                    </table>
                </div>
            </section>
        </section>
    </main>

    <script>
        const dropZone = document.getElementById('drop-zone');
        const fileInput = document.getElementById('file-input');
        const browseBtn = document.getElementById('browse-btn');
        const fileList = document.getElementById('file-list');
        const uploadBtn = document.getElementById('upload-btn');
        const uploadSpinner = document.getElementById('upload-spinner');
        const translateBtn = document.getElementById('translate-btn');
        const uploadFolderInput = document.getElementById('upload-folder');
        const outputFolderInput = document.getElementById('output-folder');
        const uploadStatus = document.getElementById('upload-status');
        const translateStatus = document.getElementById('translate-status');
        const benchTable = document.getElementById('bench-table');
        const uploadFolderPill = document.getElementById('upload-folder-pill');
        const outputFolderPill = document.getElementById('output-folder-pill');
        const batchStatus = document.getElementById('batch-status');
        const formatSelect = document.getElementById('format-select');
        const resumableToggle = document.getElementById('resumable-toggle');
        const existingUploadInput = document.getElementById('existing-upload-id');
        const loadBatchBtn = document.getElementById('load-batch-btn');
        const loadStatus = document.getElementById('load-status');

        let pendingFiles = [];
        let uploadedFiles = [];
        let uploadId = null;
        const progressBars = new Map();
        const CHUNK_SIZE = 16 * 1024 * 1024;

        function nowToken() {
            const d = new Date();
            const pad = (n) => String(n).padStart(2, '0');
            return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
        }

        function ensureFolderDefaults() {
            if (!uploadFolderInput.value.trim()) {
                uploadFolderInput.value = `batch-${nowToken()}`;
            }
            if (!outputFolderInput.value.trim()) {
                outputFolderInput.value = `output-${nowToken()}`;
            }
        }

        ensureFolderDefaults();

        browseBtn.addEventListener('click', () => fileInput.click());
        fileInput.addEventListener('change', (e) => setFiles(Array.from(e.target.files)));

        dropZone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropZone.classList.add('dragover');
        });
        dropZone.addEventListener('dragleave', (e) => {
            e.preventDefault();
            dropZone.classList.remove('dragover');
        });
        dropZone.addEventListener('drop', (e) => {
            e.preventDefault();
            dropZone.classList.remove('dragover');
            setFiles(Array.from(e.dataTransfer.files));
        });

        function setFiles(files) {
            pendingFiles = files;
            renderFileList();
            uploadStatus.textContent = files.length ? `${files.length} file(s) ready to upload.` : 'Waiting for files.';
        }

        function renderFileList() {
            fileList.innerHTML = '';
            progressBars.clear();
            pendingFiles.forEach((file) => {
                const row = document.createElement('div');
                row.className = 'file-item';

                const name = document.createElement('span');
                name.className = 'file-name';
                name.textContent = file.name;
                name.title = file.name;

                const size = document.createElement('span');
                size.className = 'file-size';
                size.textContent = formatBytes(file.size);

                row.appendChild(name);
                row.appendChild(size);

                const track = document.createElement('div');
                track.className = 'progress-track';
                const bar = document.createElement('div');
                bar.className = 'progress-bar';
                track.appendChild(bar);
                row.appendChild(track);
                progressBars.set(file.name, bar);

                fileList.appendChild(row);
            });
        }

        function renderUploadedList(files) {
            fileList.innerHTML = '';
            progressBars.clear();
            files.forEach((file) => {
                const row = document.createElement('div');
                row.className = 'file-item';

                const name = document.createElement('span');
                name.className = 'file-name';
                name.textContent = file.name;
                name.title = file.name;

                const size = document.createElement('span');
                size.className = 'file-size';
                size.textContent = formatBytes(file.size_bytes || 0);

                row.appendChild(name);
                row.appendChild(size);

                const track = document.createElement('div');
                track.className = 'progress-track';
                const bar = document.createElement('div');
                bar.className = 'progress-bar';
                bar.style.width = '100%';
                track.appendChild(bar);
                row.appendChild(track);

                fileList.appendChild(row);
            });
        }

        function setUploadBusy(isBusy) {
            uploadBtn.disabled = isBusy;
            browseBtn.disabled = isBusy;
            fileInput.disabled = isBusy;
            loadBatchBtn.disabled = isBusy;
            uploadSpinner.style.display = isBusy ? 'inline-block' : 'none';
        }

        function updateProgress(fileName, pct) {
            const bar = progressBars.get(fileName);
            if (!bar) return;
            const clamped = Math.max(0, Math.min(100, pct));
            bar.style.width = `${clamped.toFixed(1)}%`;
        }

        async function uploadStandard(files) {
            const formData = new FormData();
            formData.append('folder', uploadFolderInput.value.trim());
            files.forEach((file) => formData.append('files', file));

            const response = await fetch('/stdf-convert-benchmark/upload', { method: 'POST', body: formData });
            if (!response.ok) throw new Error(await response.text());
            return response.json();
        }

        async function initUpload() {
            const payload = {
                folder: uploadFolderInput.value.trim(),
                allow_existing: true
            };
            const response = await fetch('/stdf-convert-benchmark/upload/init', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            if (!response.ok) throw new Error(await response.text());
            return response.json();
        }

        async function fetchUploadStatus(uploadId, fileName) {
            const params = new URLSearchParams({
                upload_id: uploadId,
                file_name: fileName
            });
            const response = await fetch(`/stdf-convert-benchmark/upload/status?${params.toString()}`);
            if (!response.ok) return null;
            return response.json();
        }

        async function uploadFileInChunks(file, uploadId) {
            const totalChunks = Math.ceil(file.size / CHUNK_SIZE);
            let received = new Set();
            const status = await fetchUploadStatus(uploadId, file.name);
            if (status && status.completed) {
                updateProgress(file.name, 100);
                return { name: file.name, size_bytes: file.size };
            }
            if (status && Array.isArray(status.received_chunks)) {
                received = new Set(status.received_chunks);
            }

            let completedCount = received.size;
            updateProgress(file.name, (completedCount / totalChunks) * 100);

            let lastInfo = null;
            for (let index = 0; index < totalChunks; index += 1) {
                if (received.has(index)) {
                    continue;
                }

                const start = index * CHUNK_SIZE;
                const end = Math.min(start + CHUNK_SIZE, file.size);
                const chunk = file.slice(start, end);
                const params = new URLSearchParams({
                    upload_id: uploadId,
                    file_name: file.name,
                    chunk_index: String(index),
                    total_chunks: String(totalChunks),
                    chunk_size: String(CHUNK_SIZE),
                    total_size: String(file.size)
                });

                const response = await fetch(`/stdf-convert-benchmark/upload/chunk?${params.toString()}`,
                    { method: 'POST', body: chunk }
                );
                if (!response.ok) throw new Error(await response.text());
                lastInfo = await response.json();
                completedCount += 1;
                const pct = (completedCount / totalChunks) * 100;
                updateProgress(file.name, pct);
                uploadStatus.textContent = `Uploading ${file.name} (${completedCount}/${totalChunks} chunks)...`;
            }

            return lastInfo ? lastInfo.file : { name: file.name, size_bytes: file.size };
        }

        async function uploadResumable(files) {
            const init = await initUpload();
            uploadId = init.upload_id;
            uploadFolderPill.textContent = uploadId;

            const uploaded = [];
            for (const file of files) {
                const info = await uploadFileInChunks(file, uploadId);
                uploaded.push(info);
            }

            return { upload_id: uploadId, files: uploaded };
        }

        uploadBtn.addEventListener('click', async () => {
            if (!pendingFiles.length) return;
            ensureFolderDefaults();
            uploadStatus.textContent = 'Uploading...';
            setUploadBusy(true);

            try {
                const data = resumableToggle.checked
                    ? await uploadResumable(pendingFiles)
                    : await uploadStandard(pendingFiles);

                uploadId = data.upload_id;
                uploadedFiles = data.files || [];
                uploadFolderPill.textContent = data.upload_id;
                uploadFolderInput.value = data.upload_id;
                uploadStatus.textContent = `Uploaded ${uploadedFiles.length} file(s) to ${data.upload_id}.`;
                translateBtn.disabled = false;
                translateStatus.textContent = 'Ready to translate.';
                renderUploadedList(uploadedFiles);
            } catch (err) {
                uploadStatus.textContent = `Upload failed: ${err.message}`;
            } finally {
                setUploadBusy(false);
            }
        });

        loadBatchBtn.addEventListener('click', async () => {
            const desiredId = existingUploadInput.value.trim();
            if (!desiredId) {
                loadStatus.textContent = 'Enter an upload ID to load.';
                return;
            }
            setUploadBusy(true);
            loadStatus.textContent = 'Loading batch...';
            try {
                const params = new URLSearchParams({ upload_id: desiredId });
                const response = await fetch(`/stdf-convert-benchmark/upload/list?${params.toString()}`);
                if (!response.ok) throw new Error(await response.text());
                const data = await response.json();
                uploadId = data.upload_id;
                uploadedFiles = data.files || [];
                uploadFolderPill.textContent = uploadId;
                uploadFolderInput.value = uploadId;
                uploadStatus.textContent = `Loaded ${uploadedFiles.length} file(s) from ${uploadId}.`;
                translateBtn.disabled = false;
                translateStatus.textContent = 'Ready to translate.';
                loadStatus.textContent = 'Batch loaded.';
                renderUploadedList(uploadedFiles);
            } catch (err) {
                loadStatus.textContent = `Load failed: ${err.message}`;
            } finally {
                setUploadBusy(false);
            }
        });

        translateBtn.addEventListener('click', async () => {
            if (!uploadId) return;
            ensureFolderDefaults();
            outputFolderPill.textContent = outputFolderInput.value.trim();
            translateStatus.textContent = 'Translation started.';
            translateBtn.disabled = true;
            batchStatus.textContent = 'Running';
            benchTable.innerHTML = '';

            const rowMap = new Map();
            uploadedFiles.forEach((file) => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td class="mono file-cell"></td>
                    <td></td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td class="output-cell">-</td>
                    <td><span class="badge">queued</span></td>
                `;
                const cells = tr.querySelectorAll('td');
                cells[0].textContent = file.name;
                cells[0].title = file.name;
                cells[1].textContent = formatBytes(file.size_bytes || 0);
                benchTable.appendChild(tr);
                rowMap.set(file.name, tr);
            });

            const payload = {
                upload_id: uploadId,
                output_folder: outputFolderInput.value.trim(),
                format: formatSelect.value
            };

            try {
                const response = await fetch('/stdf-convert-benchmark/translate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });

                if (!response.ok) throw new Error(await response.text());

                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let buffer = '';

                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    buffer += decoder.decode(value, { stream: true });
                    const parts = buffer.split('\n\n');
                    buffer = parts.pop() || '';
                    parts.forEach((chunk) => {
                        const line = chunk.trim();
                        if (!line.startsWith('data:')) return;
                        const jsonText = line.slice(5).trim();
                        if (!jsonText) return;
                        handleEvent(JSON.parse(jsonText), rowMap);
                    });
                }
            } catch (err) {
                translateStatus.textContent = `Translation failed: ${err.message}`;
                batchStatus.textContent = 'Error';
            } finally {
                translateBtn.disabled = false;
            }
        });

        function handleEvent(evt, rowMap) {
            if (evt.type === 'batch_start') {
                batchStatus.textContent = `Running (${evt.total_files} files)`;
                return;
            }
            if (evt.type === 'batch_error') {
                batchStatus.textContent = 'Error';
                translateStatus.textContent = evt.message || 'Translation failed.';
                return;
            }
            if (evt.type === 'batch_done') {
                batchStatus.textContent = 'Complete';
                translateStatus.textContent = 'Translation finished.';
                return;
            }

            let row = rowMap.get(evt.file);
            if (!row && evt.type === 'file_error') {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td class="mono file-cell"></td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td class="output-cell">-</td>
                    <td><span class="badge error">error</span></td>
                `;
                const cells = tr.querySelectorAll('td');
                cells[0].textContent = evt.file || 'unknown';
                cells[0].title = evt.file || 'unknown';
                cells[5].textContent = evt.message || 'Translation failed';
                benchTable.appendChild(tr);
                rowMap.set(evt.file, tr);
                row = tr;
            }
            if (!row) return;
            const cells = row.querySelectorAll('td');
            if (evt.type === 'file_start') {
                cells[2].textContent = formatTime(evt.start_ms);
                cells[6].innerHTML = '<span class="spinner" style="display:inline-block" aria-hidden="true"></span> <span class="badge">running</span>';
            }
            if (evt.type === 'file_done') {
                cells[3].textContent = formatTime(evt.end_ms);
                cells[4].textContent = formatDuration(evt.duration_ms);
                const sizeText = formatBytes(evt.output_size_bytes);
                const safeUrl = evt.output_url || '';
                if (safeUrl) {
                    cells[5].innerHTML = '';
                    const link = document.createElement('a');
                    link.href = safeUrl;
                    link.setAttribute('download', '');
                    link.rel = 'noopener';
                    link.textContent = evt.output_name;
                    const sizeSpan = document.createElement('span');
                    sizeSpan.textContent = ` (${sizeText}) `;
                    const btn = document.createElement('button');
                    btn.className = 'btn secondary';
                    btn.textContent = 'View';
                    btn.addEventListener('click', () => openViewer(safeUrl));
                    cells[5].appendChild(link);
                    cells[5].appendChild(sizeSpan);
                    cells[5].appendChild(btn);
                } else {
                    cells[5].textContent = `${evt.output_name} (${sizeText})`;
                }
                cells[6].innerHTML = '<span class="badge done">done</span>';
            }
            if (evt.type === 'file_error') {
                cells[6].innerHTML = '<span class="badge error">error</span>';
                cells[5].textContent = evt.message || 'Translation failed';
            }
        }

        function formatBytes(bytes, decimals = 1) {
            if (!+bytes) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return `${parseFloat((bytes / Math.pow(k, i)).toFixed(decimals))} ${sizes[i]}`;
        }

        function formatTime(ms) {
            if (!ms) return '-';
            return new Date(ms).toLocaleTimeString();
        }

        function formatDuration(ms) {
            if (!ms && ms !== 0) return '-';
            const totalMs = Math.max(0, Math.round(ms));
            const hours = Math.floor(totalMs / 3600000);
            const minutes = Math.floor((totalMs % 3600000) / 60000);
            const seconds = Math.floor((totalMs % 60000) / 1000);
            const millis = totalMs % 1000;
            const pad2 = (n) => String(n).padStart(2, '0');
            const pad3 = (n) => String(n).padStart(3, '0');
            if (hours > 0) {
                return `${hours}h ${pad2(minutes)}m ${pad2(seconds)}.${pad3(millis)}s`;
            }
            if (minutes > 0) {
                return `${minutes}m ${pad2(seconds)}.${pad3(millis)}s`;
            }
            return `${seconds}.${pad3(millis)}s`;
        }

        // Viewer modal logic
        async function openViewer(url) {
            if (window.__viewer_opening) {
                console.log('openViewer ignored (already opening)', url);
                return;
            }
            window.__viewer_opening = true;
            console.log('openViewer called', url);
            const modal = document.getElementById('viewer-modal');
            const treeContainer = document.getElementById('viewer-tree');
            const textContainer = document.getElementById('viewer-text');
            const viewerSpinner = document.getElementById('viewer-spinner');
            if (treeContainer) treeContainer.innerHTML = '';
            if (textContainer) textContainer.innerHTML = 'Loading...';
            modal.style.display = 'block';
            // ensure force-raw checkbox exists (insert dynamically if modal HTML doesn't include it)
            if (!document.getElementById('viewer-force-raw')) {
                try {
                    const header = modal.querySelector('div > div');
                    const label = document.createElement('label');
                    label.style.marginLeft = '12px';
                    label.style.display = 'flex';
                    label.style.alignItems = 'center';
                    label.style.gap = '6px';
                    label.innerHTML = `<input id="viewer-force-raw" type="checkbox"> Force raw`;
                    if (header) header.insertBefore(label, header.children[3] || null);
                } catch (e) {
                    // ignore DOM insertion errors
                }
            }
            try {
                if (viewerSpinner) viewerSpinner.style.display = 'inline-block';
                const head = await fetch(url, { method: 'GET', headers: { 'Range': 'bytes=0-0' } });
                const ct = head.headers.get('content-type') || '';
                let total = null;
                const cr = head.headers.get('content-range');
                if (cr && cr.includes('/')) {
                    const parts = cr.split('/');
                    total = parseInt(parts[1], 10);
                } else {
                    const cl = head.headers.get('content-length');
                    if (cl) total = parseInt(cl, 10);
                }

                const xmlThreshold = 5 * 1024 * 1024; // 5MB
                const forceRaw = document.getElementById('viewer-force-raw') && document.getElementById('viewer-force-raw').checked;
                if (!forceRaw && ct.includes('xml') && total !== null && total <= xmlThreshold) {
                    try {
                        const res = await fetch(url);
                        const text = await res.text();
                        renderXmlTree(text);
                        document.getElementById('viewer-tab-tree').click();
                    } catch (e) {
                        treeContainer.innerHTML = '';
                        textContainer.textContent = 'Error loading file: ' + e;
                    }
                } else {
                    // show text chunk viewer
                    const chunkSize = 1024 * 1024; // 1MB
                    try {
                        await loadTextChunk(url, 0, chunkSize);
                        document.getElementById('viewer-tab-text').click();
                        // store state
                        modal.dataset.url = url;
                        modal.dataset.offset = chunkSize;
                        modal.dataset.total = total || '';
                    } catch (e) {
                        treeContainer.innerHTML = '';
                        textContainer.textContent = 'Error loading file: ' + e;
                    }
                }
            } finally {
                if (viewerSpinner) viewerSpinner.style.display = 'none';
                window.__viewer_opening = false;
            }
        }

        async function loadTextChunk(url, start, chunkSize) {
            const end = start + chunkSize - 1;
            const viewerSpinner = document.getElementById('viewer-spinner');
            if (viewerSpinner) viewerSpinner.style.display = 'inline-block';
            const res = await fetch(url, { headers: { 'Range': `bytes=${start}-${end}` } });
            if (!res.ok) {
                if (viewerSpinner) viewerSpinner.style.display = 'none';
                throw new Error('Chunk fetch failed: ' + res.status);
            }
            const txt = await res.text();
            const pre = document.getElementById('viewer-text-pre');
            if (start === 0) pre.textContent = txt; else pre.textContent += '\n' + txt;
            const loadMoreBtn = document.getElementById('viewer-load-more');
            const modal = document.getElementById('viewer-modal');
            const total = modal.dataset.total ? parseInt(modal.dataset.total, 10) : null;
            modal.dataset.offset = (start + txt.length).toString();
            if (total && (start + txt.length) >= total) {
                loadMoreBtn.style.display = 'none';
            } else {
                loadMoreBtn.style.display = 'inline-block';
            }
            try {
                if (window.hljs) {
                    pre.classList.add('hljs');
                    hljs.highlightElement(pre);
                }
            } catch (e) {
                // ignore highlighting errors
            }
            if (viewerSpinner) viewerSpinner.style.display = 'none';
        }

        function renderXmlTree(xmlText) {
            const parser = new DOMParser();
            const doc = parser.parseFromString(xmlText, 'application/xml');
            const err = doc.querySelector('parsererror');
            const tree = document.getElementById('viewer-tree');
            tree.innerHTML = '';
            if (err) {
                tree.textContent = 'XML parse error — showing raw text instead.';
                document.getElementById('viewer-text-pre').textContent = xmlText;
                document.getElementById('viewer-tab-text').click();
                return;
            }
            function nodeToDetails(node) {
                const d = document.createElement('details');
                const s = document.createElement('summary');
                if (node.nodeType === Node.ELEMENT_NODE) {
                    s.textContent = '<' + node.nodeName + '>';
                    d.appendChild(s);
                    const attrCount = node.attributes ? node.attributes.length : 0;
                    if (attrCount > 0) {
                        const attrDetails = document.createElement('details');
                        const attrSummary = document.createElement('summary');
                        attrSummary.textContent = `attributes (${attrCount})`;
                        attrSummary.style.marginLeft = '8px';
                        attrDetails.appendChild(attrSummary);
                        for (let attr of node.attributes || []) {
                            const a = document.createElement('div');
                            a.textContent = `@${attr.name} = ${attr.value}`;
                            a.style.marginLeft = '12px';
                            attrDetails.appendChild(a);
                        }
                        d.appendChild(attrDetails);
                    }
                    // Collect element children and render text nodes immediately.
                    const elementChildren = [];
                    for (let child of node.childNodes) {
                        if (child.nodeType === Node.TEXT_NODE) {
                            const t = child.textContent.trim();
                            if (t) {
                                const p = document.createElement('div');
                                p.textContent = t;
                                p.style.marginLeft = '12px';
                                d.appendChild(p);
                            }
                        } else if (child.nodeType === Node.ELEMENT_NODE) {
                            elementChildren.push(child);
                        } else {
                            d.appendChild(nodeToDetails(child));
                        }
                    }

                    // If there are many element children, render in batches to avoid huge DOMs.
                    if (elementChildren.length > 0) {
                        const batchSize = 100; // tune as needed
                        const container = document.createElement('div');
                        container.style.marginLeft = '8px';

                        const renderBatch = (start) => {
                            const end = Math.min(start + batchSize, elementChildren.length);
                            for (let i = start; i < end; i++) {
                                container.appendChild(nodeToDetails(elementChildren[i]));
                            }
                            if (end < elementChildren.length) {
                                const moreBtn = document.createElement('button');
                                moreBtn.className = 'btn';
                                moreBtn.textContent = `Load more (${end}/${elementChildren.length})`;
                                moreBtn.style.margin = '6px 0';
                                moreBtn.onclick = () => {
                                    moreBtn.remove();
                                    renderBatch(end);
                                };
                                container.appendChild(moreBtn);
                            }
                        };

                        renderBatch(0);
                        d.appendChild(container);
                    }
                } else if (node.nodeType === Node.DOCUMENT_NODE) {
                    for (let c of node.childNodes) d.appendChild(nodeToDetails(c));
                } else {
                    s.textContent = node.nodeName;
                    d.appendChild(s);
                }
                return d;
            }
            const rootDetails = nodeToDetails(doc);
            tree.appendChild(rootDetails);
        }

        function closeViewer() {
            const modal = document.getElementById('viewer-modal');
            if (modal) {
                modal.style.display = 'none';
                try { modal.dataset.url = ''; } catch (e) {}
                try { modal.dataset.offset = ''; } catch (e) {}
                try { modal.dataset.total = ''; } catch (e) {}
            }
            const pre = document.getElementById('viewer-text-pre');
            if (pre) pre.textContent = '';
            const tree = document.getElementById('viewer-tree');
            if (tree) tree.innerHTML = '';
            const spinner = document.getElementById('viewer-spinner');
            if (spinner) spinner.style.display = 'none';
        }

        // Persist and initialize the viewer 'Force raw' checkbox using localStorage
        (function() {
            function setupToggle() {
                const cb = document.getElementById('viewer-force-raw');
                if (!cb) return;
                try {
                    const val = localStorage.getItem('viewer_force_raw');
                    cb.checked = val === '1';
                } catch (e) {}
                cb.removeEventListener('change', toggleHandler);
                cb.addEventListener('change', toggleHandler);
            }
            function toggleHandler(e) {
                try { localStorage.setItem('viewer_force_raw', e.target.checked ? '1' : '0'); } catch (err) {}
            }
            // run now and watch for future insertion of the checkbox
            setupToggle();
            const mo = new MutationObserver((mutations) => { setupToggle(); });
            mo.observe(document.body, { childList: true, subtree: true });
        })();

        // List outputs UI
        async function listOutputs() {
            const folder = document.getElementById('outputs-folder-input').value.trim();
            if (!folder) return alert('Enter an outputs folder name');
            const modal = document.getElementById('outputs-modal');
            const list = document.getElementById('outputs-list');
            list.innerHTML = 'Loading...';
            modal.style.display = 'block';
            try {
                const res = await fetch(`/stdf-convert-benchmark/outputs/${encodeURIComponent(folder)}`);
                if (!res.ok) throw new Error('Fetch failed: ' + res.status);
                const files = await res.json();
                list.innerHTML = '';
                if (!files || files.length === 0) list.textContent = 'No files found';
                for (const f of files) {
                    const r = document.createElement('div');
                    r.style.display = 'flex'; r.style.alignItems = 'center'; r.style.gap = '8px'; r.style.padding = '6px 0';
                    const name = document.createElement('div'); name.textContent = f.name; name.style.flex = '1'; name.className = 'mono file-cell';
                    const size = document.createElement('div'); size.textContent = (f.size/1024).toFixed(1) + ' KB'; size.style.color = 'var(--ink-muted)';
                    const btn = document.createElement('button');
                    btn.type = 'button';
                    btn.className = 'btn secondary';
                    btn.textContent = 'View';
                    btn.addEventListener('click', () => {
                        console.log('outputs list: View clicked', f.url);
                        openViewer(f.url);
                    });
                    // Download button
                    const dl = document.createElement('a');
                    dl.className = 'btn';
                    dl.textContent = 'Download';
                    dl.href = f.url;
                    dl.setAttribute('download', '');
                    dl.style.marginLeft = '6px';
                    r.appendChild(name); r.appendChild(size); r.appendChild(btn); r.appendChild(dl);
                    list.appendChild(r);
                }
            } catch (e) {
                list.textContent = 'Error: ' + e;
            }
        }

        async function listFolders() {
            const modal = document.getElementById('outputs-modal');
            const list = document.getElementById('outputs-list');
            list.innerHTML = 'Loading...';
            modal.style.display = 'block';
            try {
                const res = await fetch(`/stdf-convert-benchmark/outputs`);
                if (!res.ok) throw new Error('Fetch failed: ' + res.status);
                const folders = await res.json();
                list.innerHTML = '';
                if (!folders || folders.length === 0) list.textContent = 'No folders found';
                for (const f of folders) {
                    const r = document.createElement('div');
                    r.style.display = 'flex'; r.style.alignItems = 'center'; r.style.gap = '8px'; r.style.padding = '6px 0';
                    const name = document.createElement('div'); name.textContent = f.name; name.style.flex = '1'; name.className = 'mono file-cell';
                    const count = document.createElement('div'); count.textContent = `${f.count} files`; count.style.color = 'var(--ink-muted)';
                    const btn = document.createElement('button');
                    btn.type = 'button';
                    btn.className = 'btn secondary';
                    btn.textContent = 'Open';
                    btn.addEventListener('click', () => {
                        console.log('folders list: Open clicked', f.name);
                        document.getElementById('outputs-folder-input').value = f.name;
                        listOutputs();
                    });
                    r.appendChild(name); r.appendChild(count); r.appendChild(btn);
                    list.appendChild(r);
                }
            } catch (e) {
                list.textContent = 'Error: ' + e;
            }
        }
        // wire the List outputs button
        (function(){
            const btn = document.getElementById('list-outputs-btn');
            if (btn) btn.addEventListener('click', listOutputs);
            const fbtn = document.getElementById('list-folders-btn');
            if (fbtn) fbtn.addEventListener('click', listFolders);
        })();
    </script>

    <!-- Viewer modal -->
    <div id="viewer-modal" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.6); align-items:center; justify-content:center; z-index:1100;">
        <div style="background:#fff; width:92%; max-width:980px; height:80%; margin:auto; border-radius:12px; overflow:auto; padding:12px; position:relative;">
            <button onclick="closeViewer()" style="position:absolute; right:12px; top:12px;" class="btn">Close</button>
            <div style="display:flex; gap:8px; align-items:center; margin-bottom:8px;">
                <button id="viewer-tab-tree" type="button" class="btn secondary" onclick="(function(){document.getElementById('viewer-tree').style.display='block'; document.getElementById('viewer-text').style.display='none';})();">Tree</button>
                <button id="viewer-tab-text" type="button" class="btn" onclick="(function(){document.getElementById('viewer-tree').style.display='none'; document.getElementById('viewer-text').style.display='block';})();">Text</button>
                <div style="flex:1"></div>
                <button id="viewer-load-more" type="button" class="btn" style="display:none;" onclick="(async function(){ const modal=document.getElementById('viewer-modal'); const url=modal.dataset.url; const offset=parseInt(modal.dataset.offset||'0',10); await loadTextChunk(url, offset, 1024*1024); })()">Load more</button>
            </div>
            <div id="viewer-tree" style="display:none; overflow:auto; max-height:calc(100% - 80px); padding:8px; border-top:1px solid rgba(0,0,0,0.04);"></div>
            <div id="viewer-text" style="display:none; overflow:auto; max-height:calc(100% - 80px); padding:8px; border-top:1px solid rgba(0,0,0,0.04);">
                <pre id="viewer-text-pre" style="white-space:pre-wrap; word-break:break-word; font-family: IBM Plex Mono, monospace; font-size:0.85rem;"> </pre>
            </div>
        </div>
    </div>

    <!-- Outputs modal -->
    <div id="outputs-modal" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.5); align-items:center; justify-content:center; z-index:1000;">
        <div style="background:#fff; width:90%; max-width:820px; height:70%; margin:auto; border-radius:12px; overflow:auto; padding:16px; position:relative;">
            <button onclick="document.getElementById('outputs-modal').style.display='none'" style="position:absolute; right:12px; top:12px;" class="btn">Close</button>
            <h3>Outputs</h3>
            <div id="outputs-list" style="margin-top:12px; overflow:auto; max-height:calc(100% - 64px);"></div>
        </div>
    </div>

</body>
</html>
"#;

#[tokio::main]
async fn main() {
    if let Err(e) = std::fs::create_dir_all(LOG_ROOT) {
        eprintln!("Failed to create log directory {}: {}", LOG_ROOT, e);
    }

    let file_appender = tracing_appender::rolling::daily(LOG_ROOT, "stdf-translator.log");
    let (file_writer, _file_guard) = tracing_appender::non_blocking(file_appender);

    let stdout_layer = tracing_subscriber::fmt::layer()
        .with_target(false)
        .with_writer(std::io::stdout);
    let file_layer = tracing_subscriber::fmt::layer()
        .json()
        .with_target(true)
        .with_writer(file_writer);

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new("info,stdf_translator=debug"))
        .with(stdout_layer)
        .with(file_layer)
        .init();

    let args = Args::parse();

    if args.server {
        run_server().await;
    } else if let Some(input_path) = args.input {
        run_cli(input_path, args.output, args.format);
    } else {
        use clap::CommandFactory;
        let mut cmd = Args::command();
        cmd.print_help().unwrap();
    }
}

async fn run_server() {
    let app = Router::new()
        .route("/", get(index_handler))
        .route("/upload", post(upload_files))
        .route("/upload/init", post(init_upload))
        .route("/upload/chunk", post(upload_chunk))
        .route("/upload/status", get(upload_status))
        .route("/upload/list", get(upload_list))
        .route("/translate", post(translate_batch))
        .route("/outputs/:folder/:file", get(get_output_file))
        .route("/outputs", get(list_output_folders))
        .route("/outputs/:folder", get(list_output_files))
        .route("/convert", post(convert_stdf_web))
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(TraceLayer::new_for_http());

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("Server listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn index_handler() -> Html<&'static str> {
    Html(INDEX_HTML)
}

async fn upload_files(mut multipart: Multipart) -> Response {
    let mut folder_hint: Option<String> = None;
    let mut upload_dir: Option<PathBuf> = None;
    let mut upload_id: Option<String> = None;
    let mut files: Vec<UploadFileInfo> = Vec::new();

    loop {
        let field = match multipart.next_field().await {
            Ok(Some(field)) => field,
            Ok(None) => break,
            Err(e) => return (StatusCode::BAD_REQUEST, format!("Multipart error: {}", e)).into_response(),
        };

        let name = field.name().unwrap_or("").to_string();
        if name == "folder" {
            let text = field.text().await.unwrap_or_default();
            if !text.trim().is_empty() {
                folder_hint = Some(text.trim().to_string());
            }
            continue;
        }

        if name != "file" && name != "files" {
            continue;
        }

        if upload_dir.is_none() {
            let hint = folder_hint.clone();
            let (dir, id) = match ensure_upload_dir(hint, false).await {
                Ok(result) => result,
                Err(resp) => return resp,
            };
            upload_dir = Some(dir);
            upload_id = Some(id);
        }

        let original_name = field.file_name().unwrap_or("unknown.stdf");
        let safe_name = sanitize_file_name(original_name);
        let target_dir = upload_dir.as_ref().unwrap();
        let file_path = target_dir.join(&safe_name);

        let out_file = match tokio::fs::File::create(&file_path).await {
            Ok(f) => f,
            Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Upload file error: {}", e)).into_response(),
        };

        let mut out_file = tokio::io::BufWriter::with_capacity(UPLOAD_BUFFER_BYTES, out_file);

        let mut size_bytes: u64 = 0;
        let mut field = field;
        while let Ok(Some(chunk)) = field.chunk().await {
            size_bytes += chunk.len() as u64;
            if let Err(e) = out_file.write_all(&chunk).await {
                return (StatusCode::INTERNAL_SERVER_ERROR, format!("Upload write error: {}", e)).into_response();
            }
        }
        if let Err(e) = out_file.flush().await {
            return (StatusCode::INTERNAL_SERVER_ERROR, format!("Upload write flush error: {}", e)).into_response();
        }
        // Ensure data is persisted to storage before returning
        let async_file = out_file.into_inner();
        if let Err(e) = async_file.sync_all().await {
            tracing::warn!("Upload file sync_all failed: {}", e);
        }
        drop(async_file);

        files.push(UploadFileInfo {
            name: safe_name,
            size_bytes,
        });
    }

    let upload_dir = match upload_dir {
        Some(dir) => dir,
        None => return (StatusCode::BAD_REQUEST, "No files uploaded").into_response(),
    };

    let upload_id = upload_id.unwrap_or_else(|| format!("batch-{}", now_ms()));
    let response = UploadResponse {
        upload_id,
        upload_folder: upload_dir.to_string_lossy().to_string(),
        files,
    };

    Json(response).into_response()
}

async fn init_upload(Json(payload): Json<UploadInitRequest>) -> Response {
    tracing::info!("📤 init_upload: folder={:?}, allow_existing={}", payload.folder, payload.allow_existing.unwrap_or(false));
    
    let allow_existing = payload.allow_existing.unwrap_or(false);
    let (upload_dir, upload_id) = match ensure_upload_dir(payload.folder, allow_existing).await {
        Ok(result) => result,
        Err(resp) => return resp,
    };

    tracing::info!("✅ init_upload created: upload_id={}, dir={}", upload_id, upload_dir.display());
    
    let response = UploadInitResponse {
        upload_id,
        upload_folder: upload_dir.to_string_lossy().to_string(),
    };

    Json(response).into_response()
}

async fn upload_chunk(Query(params): Query<ChunkUploadQuery>, body: Bytes) -> Response {
    tracing::info!("📦 upload_chunk called: upload_id={}, file={}, chunk_index={}/{}, body_size={}", 
        params.upload_id, params.file_name, params.chunk_index, params.total_chunks, body.len());
    
    if params.chunk_size == 0 || params.total_chunks == 0 {
        tracing::warn!("Invalid chunk metadata: chunk_size={}, total_chunks={}", params.chunk_size, params.total_chunks);
        return (StatusCode::BAD_REQUEST, "Invalid chunk metadata").into_response();
    }
    if params.chunk_index >= params.total_chunks {
        return (StatusCode::BAD_REQUEST, "Chunk index out of range").into_response();
    }

    let upload_id = sanitize_folder_name(&params.upload_id);
    if upload_id.is_empty() {
        return (StatusCode::BAD_REQUEST, "Invalid upload id").into_response();
    }
    let safe_name = sanitize_file_name(&params.file_name);

    if let Err(e) = tokio::fs::create_dir_all(UPLOAD_ROOT).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Upload root error: {}", e)).into_response();
    }

    let upload_dir = Path::new(UPLOAD_ROOT).join(&upload_id);
    if !upload_dir.exists() {
        if let Err(e) = tokio::fs::create_dir_all(&upload_dir).await {
            return (StatusCode::INTERNAL_SERVER_ERROR, format!("Upload folder error: {}", e)).into_response();
        }
    }

    let final_path = upload_dir.join(&safe_name);
    if final_path.exists() {
        let response = ChunkUploadResponse {
            upload_id,
            file: UploadFileInfo {
                name: safe_name,
                size_bytes: params.total_size,
            },
            complete: true,
            received_chunks: params.total_chunks,
            total_chunks: params.total_chunks,
        };
        return Json(response).into_response();
    }

    let chunk_dir = upload_dir.join(CHUNK_DIR_NAME);
    if let Err(e) = tokio::fs::create_dir_all(&chunk_dir).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Chunk folder error: {}", e)).into_response();
    }

    let state_path = chunk_dir.join(format!("{}.state.json", safe_name));
    let part_path = chunk_dir.join(format!("{}.part", safe_name));

    let mut state = match load_chunk_state(&state_path, &params).await {
        Ok(state) => state,
        Err(err) => return (StatusCode::BAD_REQUEST, err).into_response(),
    };

    if state.received.len() != params.total_chunks as usize {
        return (StatusCode::BAD_REQUEST, "Chunk state mismatch").into_response();
    }

    let offset = (params.chunk_index as u64).saturating_mul(params.chunk_size);
    if offset >= params.total_size {
        return (StatusCode::BAD_REQUEST, "Chunk offset out of range").into_response();
    }

    let expected_max = std::cmp::min(params.chunk_size, params.total_size.saturating_sub(offset));
    if body.len() as u64 > expected_max {
        return (StatusCode::BAD_REQUEST, "Chunk size exceeds expected length").into_response();
    }

    let mut file = match tokio::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(&part_path)
        .await
    {
        Ok(f) => f,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Chunk open error: {}", e)).into_response(),
    };

    if let Err(e) = file.seek(SeekFrom::Start(offset)).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Chunk seek error: {}", e)).into_response();
    }
    if let Err(e) = file.write_all(&body).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Chunk write error: {}", e)).into_response();
    }
    drop(file);

    state.received[params.chunk_index as usize] = 1;
    if let Err(e) = save_chunk_state(&state_path, &state).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Chunk state error: {}", e)).into_response();
    }

    let received_count = state.received.iter().filter(|v| **v == 1).count() as u32;
    let complete = received_count == params.total_chunks;

    if complete {
        let final_path = upload_dir.join(&safe_name);
        if let Err(e) = tokio::fs::rename(&part_path, &final_path).await {
            return (StatusCode::INTERNAL_SERVER_ERROR, format!("Finalize error: {}", e)).into_response();
        }
        let _ = tokio::fs::remove_file(&state_path).await;
    }

    let response = ChunkUploadResponse {
        upload_id,
        file: UploadFileInfo {
            name: safe_name,
            size_bytes: params.total_size,
        },
        complete,
        received_chunks: received_count,
        total_chunks: params.total_chunks,
    };

    Json(response).into_response()
}

async fn upload_status(Query(params): Query<UploadStatusQuery>) -> Response {
    let upload_id = sanitize_folder_name(&params.upload_id);
    if upload_id.is_empty() {
        return (StatusCode::BAD_REQUEST, "Invalid upload id").into_response();
    }
    let safe_name = sanitize_file_name(&params.file_name);

    let upload_dir = Path::new(UPLOAD_ROOT).join(&upload_id);
    let final_path = upload_dir.join(&safe_name);
    if final_path.exists() {
        let response = UploadStatusResponse {
            upload_id,
            file: safe_name,
            total_chunks: 0,
            received_chunks: Vec::new(),
            completed: true,
        };
        return Json(response).into_response();
    }

    let state_path = upload_dir
        .join(CHUNK_DIR_NAME)
        .join(format!("{}.state.json", safe_name));
    if !state_path.exists() {
        let response = UploadStatusResponse {
            upload_id,
            file: safe_name,
            total_chunks: 0,
            received_chunks: Vec::new(),
            completed: false,
        };
        return Json(response).into_response();
    }

    let state = match tokio::fs::read(&state_path).await {
        Ok(bytes) => match serde_json::from_slice::<ChunkState>(&bytes) {
            Ok(state) => state,
            Err(_) => {
                let response = UploadStatusResponse {
                    upload_id,
                    file: safe_name,
                    total_chunks: 0,
                    received_chunks: Vec::new(),
                    completed: false,
                };
                return Json(response).into_response();
            }
        },
        Err(_) => {
            let response = UploadStatusResponse {
                upload_id,
                file: safe_name,
                total_chunks: 0,
                received_chunks: Vec::new(),
                completed: false,
            };
            return Json(response).into_response();
        }
    };

    let received_chunks = state
        .received
        .iter()
        .enumerate()
        .filter_map(|(idx, v)| if *v == 1 { Some(idx as u32) } else { None })
        .collect::<Vec<u32>>();

    let response = UploadStatusResponse {
        upload_id,
        file: safe_name,
        total_chunks: state.total_chunks,
        received_chunks,
        completed: false,
    };

    Json(response).into_response()
}

async fn upload_list(Query(params): Query<UploadListQuery>) -> Response {
    let upload_id = sanitize_folder_name(&params.upload_id);
    if upload_id.is_empty() {
        return (StatusCode::BAD_REQUEST, "Invalid upload id").into_response();
    }
    let upload_dir = Path::new(UPLOAD_ROOT).join(&upload_id);
    if !upload_dir.exists() {
        return (StatusCode::NOT_FOUND, "Upload folder not found").into_response();
    }

    let files = match list_upload_files(&upload_dir).await {
        Ok(files) => files,
        Err(err) => return (StatusCode::INTERNAL_SERVER_ERROR, err).into_response(),
    };

    let response = UploadListResponse { upload_id, files };
    Json(response).into_response()
}

async fn translate_batch(Json(payload): Json<TranslateRequest>) -> Response {
    tracing::info!(
        "translate_batch: upload_id={}, output_folder={:?}, format={:?}",
        payload.upload_id,
        payload.output_folder,
        payload.format
    );

    if let Err(e) = tokio::fs::create_dir_all(OUTPUT_ROOT).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Output root error: {}", e)).into_response();
    }

    let upload_id = sanitize_folder_name(&payload.upload_id);
    if upload_id.is_empty() {
        return (StatusCode::BAD_REQUEST, "Invalid upload id").into_response();
    }

    let output_folder = {
        let cleaned = sanitize_folder_name(&payload.output_folder);
        if cleaned.is_empty() {
            format!("output-{}", now_ms())
        } else {
            cleaned
        }
    };

    let format = payload.format.unwrap_or_else(|| "xml".to_string());
    let upload_dir = Path::new(UPLOAD_ROOT).join(&upload_id);
    if !upload_dir.exists() {
        return (StatusCode::NOT_FOUND, "Upload folder not found").into_response();
    }

    let output_dir = Path::new(OUTPUT_ROOT).join(&output_folder);
    if let Err(e) = tokio::fs::create_dir_all(&output_dir).await {
        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Output folder error: {}", e)).into_response();
    }

    let (tx, rx) = tokio::sync::mpsc::channel::<Bytes>(32);

    tokio::task::spawn_blocking(move || {
        let mut entries: Vec<PathBuf> = match std::fs::read_dir(&upload_dir) {
            Ok(read_dir) => read_dir
                .filter_map(|entry| entry.ok())
                .filter(|entry| entry.file_type().map(|t| t.is_file()).unwrap_or(false))
                .map(|entry| entry.path())
                .collect(),
            Err(e) => {
                tracing::error!("translate_batch: read_dir failed: {}", e);
                send_event(&tx, json!({"type": "batch_error", "message": e.to_string()}));
                send_event(&tx, json!({"type": "batch_done"}));
                return;
            }
        };

        entries.sort_by_key(|path| path.file_name().map(|name| name.to_os_string()));
        tracing::info!("translate_batch: found {} files in {}", entries.len(), upload_dir.display());

        let temp_dir = match tempfile::TempDir::new() {
            Ok(dir) => dir,
            Err(e) => {
                tracing::error!("translate_batch: temp dir error: {}", e);
                send_event(&tx, json!({"type": "batch_error", "message": e.to_string()}));
                send_event(&tx, json!({"type": "batch_done"}));
                return;
            }
        };

        let mut expanded_entries = Vec::new();
        for path in entries {
            match expand_input_path(&path, temp_dir.path()) {
                Ok(mut extra) => expanded_entries.append(&mut extra),
                Err(err) => {
                    let file_name = path
                        .file_name()
                        .and_then(|name| name.to_str())
                        .unwrap_or("unknown");
                    tracing::warn!("translate_batch: expand failed for {}: {}", file_name, err);
                    send_event(&tx, json!({"type": "file_error", "file": file_name, "message": err}));
                }
            }
        }

        if expanded_entries.is_empty() {
            tracing::warn!("translate_batch: no STDF files found after expansion");
            send_event(&tx, json!({"type": "batch_error", "message": "No STDF files found after expansion"}));
            send_event(&tx, json!({"type": "batch_done"}));
            return;
        }

        expanded_entries.sort_by_key(|path| path.file_name().map(|name| name.to_os_string()));
        tracing::info!("translate_batch: expanded to {} files", expanded_entries.len());
        send_event(&tx, json!({"type": "batch_start", "total_files": expanded_entries.len(), "output_folder": output_folder}));

        for path in expanded_entries {
            let file_name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or("unknown.stdf")
                .to_string();

            tracing::info!("translate_batch: processing {}", file_name);

            let start_ms = now_ms();
            let input_size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            send_event(&tx, json!({
                "type": "file_start",
                "file": file_name,
                "start_ms": start_ms,
                "input_size_bytes": input_size
            }));

            let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("output");
            let ext = if format.eq_ignore_ascii_case("text") { "txt" } else { "xml" };
            let temp_name = format!("tmp-{}-{}.{}", now_ms(), sanitize_token(stem), ext);
            let temp_path = output_dir.join(&temp_name);

            let output_file = match File::create(&temp_path) {
                Ok(f) => f,
                Err(e) => {
                    send_event(&tx, json!({"type": "file_error", "file": file_name, "message": e.to_string()}));
                    continue;
                }
            };

            let writer = BufWriter::new(output_file);
            let result = if format.eq_ignore_ascii_case("text") {
                text_translator::process_stdf_to_text(&path, &file_name, writer)
            } else {
                translator::process_stdf_stream(&path, &file_name, writer)
            };

            match result {
                Ok(meta) => {
                    let output_name = build_output_file_name(&file_name, &meta, ext);
                    let (output_path, output_name) = unique_output_path(&output_dir, &output_name);
                    if let Err(e) = std::fs::rename(&temp_path, &output_path) {
                        let _ = std::fs::remove_file(&temp_path);
                        send_event(&tx, json!({"type": "file_error", "file": file_name, "message": e.to_string()}));
                        continue;
                    }
                    let end_ms = now_ms();
                    let duration_ms = end_ms.saturating_sub(start_ms);
                    let output_size = std::fs::metadata(&output_path).map(|m| m.len()).unwrap_or(0);
                    let output_url = format!("/stdf-convert-benchmark/outputs/{}/{}", output_folder, output_name);
                    send_event(&tx, json!({
                        "type": "file_done",
                        "file": file_name,
                        "end_ms": end_ms,
                        "duration_ms": duration_ms,
                        "output_name": output_name,
                        "output_size_bytes": output_size,
                        "output_url": output_url
                    }));
                }
                Err(e) => {
                    let _ = std::fs::remove_file(&temp_path);
                    tracing::error!("translate_batch: file {} failed: {}", file_name, e);
                    send_event(&tx, json!({"type": "file_error", "file": file_name, "message": e.to_string()}));
                }
            }
        }

        send_event(&tx, json!({"type": "batch_done"}));
    });

    let stream = tokio_stream::wrappers::ReceiverStream::new(rx)
        .map(|bytes| Ok::<Bytes, Infallible>(bytes));
    let body = Body::from_stream(stream);

    Response::builder()
        .header(axum::http::header::CONTENT_TYPE, "text/event-stream")
        .header(axum::http::header::CACHE_CONTROL, "no-cache")
        .body(body)
        .unwrap()
}

async fn get_output_file(AxumPath((folder, file)): AxumPath<(String, String)>, headers: axum::http::HeaderMap) -> Response {
    let safe_folder = sanitize_folder_name(&folder);
    let safe_file = sanitize_file_name(&file);
    if safe_folder.is_empty() || safe_file.is_empty() {
        return (StatusCode::BAD_REQUEST, "Invalid path").into_response();
    }

    let target_path = Path::new(OUTPUT_ROOT).join(safe_folder).join(&safe_file);
    if !target_path.exists() {
        return (StatusCode::NOT_FOUND, "File not found").into_response();
    }

    // Support Range requests for efficient partial reads (for large file viewing)
    let metadata = match tokio::fs::metadata(&target_path).await {
        Ok(m) => m,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Metadata error: {}", e)).into_response(),
    };
    let total_len = metadata.len();

    let content_type = content_type_for_file(&safe_file);

    // Check for Range header
    if let Some(range_val) = headers.get(axum::http::header::RANGE) {
        if let Ok(range_str) = range_val.to_str() {
            if range_str.starts_with("bytes=") {
                // parse "bytes=start-end" (end optional)
                let parts: Vec<&str> = range_str[6..].split('-').collect();
                if let Ok(start) = parts.get(0).unwrap_or(&"").parse::<u64>() {
                    let end = if let Some(e) = parts.get(1).and_then(|s| if s.is_empty() { None } else { s.parse::<u64>().ok() }) {
                        e
                    } else {
                        total_len.saturating_sub(1)
                    };
                    if start >= total_len {
                        return (StatusCode::RANGE_NOT_SATISFIABLE, "Range not satisfiable").into_response();
                    }
                    let end = std::cmp::min(end, total_len.saturating_sub(1));
                    let read_len = (end - start + 1) as usize;
                    // Read range from file
                    use tokio::io::{AsyncReadExt, AsyncSeekExt};
                    let mut f = match tokio::fs::File::open(&target_path).await {
                        Ok(f) => f,
                        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Open error: {}", e)).into_response(),
                    };
                    if let Err(e) = f.seek(std::io::SeekFrom::Start(start)).await {
                        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Seek error: {}", e)).into_response();
                    }
                    let mut buf = vec![0u8; read_len];
                    if let Err(e) = f.read_exact(&mut buf).await {
                        return (StatusCode::INTERNAL_SERVER_ERROR, format!("Read error: {}", e)).into_response();
                    }
                    let content_range = format!("bytes {}-{}/{}", start, end, total_len);
                    return Response::builder()
                        .status(StatusCode::PARTIAL_CONTENT)
                        .header(axum::http::header::CONTENT_TYPE, content_type)
                        .header(axum::http::header::ACCEPT_RANGES, "bytes")
                        .header(axum::http::header::CONTENT_RANGE, content_range)
                        .header(axum::http::header::CONTENT_LENGTH, read_len.to_string())
                        .body(Body::from(buf))
                        .unwrap();
                }
            }
        }
    }

    // No Range header -> return full file
    let data = match tokio::fs::read(&target_path).await {
        Ok(bytes) => bytes,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Read error: {}", e)).into_response(),
    };

    Response::builder()
        .header(axum::http::header::CONTENT_TYPE, content_type)
        .header(axum::http::header::ACCEPT_RANGES, "bytes")
        .header(
            axum::http::header::CONTENT_DISPOSITION,
            format!("attachment; filename=\"{}\"", safe_file),
        )
        .header(axum::http::header::CONTENT_LENGTH, data.len().to_string())
        .body(Body::from(data))
        .unwrap()
}

async fn list_output_files(AxumPath((folder,)): AxumPath<(String,)>) -> Response {
    let safe_folder = sanitize_folder_name(&folder);
    if safe_folder.is_empty() {
        return (StatusCode::BAD_REQUEST, "Invalid folder").into_response();
    }
    let target_dir = Path::new(OUTPUT_ROOT).join(&safe_folder);
    if !target_dir.exists() {
        return (StatusCode::NOT_FOUND, "Folder not found").into_response();
    }

    let mut entries = match std::fs::read_dir(&target_dir) {
        Ok(rd) => rd,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Read dir error: {}", e)).into_response(),
    };

    let mut files = Vec::new();
    while let Some(Ok(ent)) = entries.next() {
        let p = ent.path();
        if p.is_file() {
            if let Some(name) = p.file_name().and_then(|s| s.to_str()) {
                let size = std::fs::metadata(&p).map(|m| m.len()).unwrap_or(0);
                let url = format!("/stdf-convert-benchmark/outputs/{}/{}", safe_folder, name);
                files.push(json!({"name": name, "size": size, "url": url}));
            }
        }
    }

    Json(json!(files)).into_response()
}

async fn list_output_folders() -> Response {
    let target = Path::new(OUTPUT_ROOT);
    if !target.exists() {
        return (StatusCode::NOT_FOUND, "Outputs root not found").into_response();
    }
    let mut entries = match std::fs::read_dir(target) {
        Ok(rd) => rd,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, format!("Read dir error: {}", e)).into_response(),
    };
    let mut folders = Vec::new();
    while let Some(Ok(ent)) = entries.next() {
        let p = ent.path();
        if p.is_dir() {
            if let Some(name) = p.file_name().and_then(|s| s.to_str()) {
                // Count files inside
                let mut count = 0usize;
                if let Ok(mut rd2) = std::fs::read_dir(&p) {
                    while let Some(Ok(_)) = rd2.next() { count += 1; }
                }
                folders.push(json!({"name": name, "count": count}));
            }
        }
    }
    Json(json!(folders)).into_response()
}

fn run_cli(input_path: String, output_path: Option<String>, format: String) {
    tracing::info!("Starting CLI conversion for {} (format: {})", input_path, format);
    let start = Instant::now();
    let path = std::path::Path::new(&input_path);
    let filename = path.file_name().unwrap_or_default().to_string_lossy();
    let ext = if format.eq_ignore_ascii_case("text") { "txt" } else { "xml" };

    if let Some(out_path) = output_path.as_ref() {
        let output_file = match File::create(out_path) {
            Ok(f) => f,
            Err(e) => {
                tracing::error!("Failed to create output file: {}", e);
                return;
            }
        };
        let writer = BufWriter::new(output_file);
        let result = if format.eq_ignore_ascii_case("text") {
            text_translator::process_stdf_to_text(path, &filename, writer)
        } else {
            translator::process_stdf_stream(path, &filename, writer)
        };

        match result {
            Ok(_) => {
                let duration = start.elapsed();
                tracing::info!("Conversion successful. Saved to {}. Time: {}", out_path, format_duration(duration));
            }
            Err(e) => tracing::error!("Conversion failed: {}", e),
        }
        return;
    }

    let output_dir = path.parent().unwrap_or_else(|| Path::new("."));
    let temp_name = format!("tmp-{}-{}.{}", now_ms(), sanitize_token(&filename), ext);
    let temp_path = output_dir.join(&temp_name);
    let output_file = match File::create(&temp_path) {
        Ok(f) => f,
        Err(e) => {
            tracing::error!("Failed to create output file: {}", e);
            return;
        }
    };
    let writer = BufWriter::new(output_file);

    let result = if format.eq_ignore_ascii_case("text") {
        text_translator::process_stdf_to_text(path, &filename, writer)
    } else {
        translator::process_stdf_stream(path, &filename, writer)
    };

    match result {
        Ok(meta) => {
            let output_name = build_output_file_name(&filename, &meta, ext);
            let (output_path, output_name) = unique_output_path(output_dir, &output_name);
            if let Err(e) = std::fs::rename(&temp_path, &output_path) {
                let _ = std::fs::remove_file(&temp_path);
                tracing::error!("Failed to rename output file: {}", e);
                return;
            }
            let duration = start.elapsed();
            tracing::info!("Conversion successful. Saved to {}. Time: {}", output_name, format_duration(duration));
        }
        Err(e) => {
            let _ = std::fs::remove_file(&temp_path);
            tracing::error!("Conversion failed: {}", e)
        }
    }
}

use std::collections::HashMap;

async fn convert_stdf_web(Query(params): Query<HashMap<String, String>>, mut multipart: Multipart) -> Response {
    let format = params.get("format").cloned().unwrap_or_else(|| "xml".to_string());

    while let Some(mut field) = multipart.next_field().await.unwrap() {
        let name = field.name().unwrap().to_string();
        if name == "file" {
            let original_name = field.file_name().unwrap_or("unknown.stdf").to_string();

            // 1. Create a named temp file
            let temp_file = match tempfile::NamedTempFile::new() {
                Ok(t) => t,
                Err(e) => return (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Temp file error: {}", e)).into_response(),
            };
            let (std_file, temp_path) = temp_file.keep().unwrap(); // Keep it to allow passing path. We will clean up manually if needed or let OS handle TMP logic.
            // Actually, NamedTempFile auto-deletes on Drop. 
            // But we need to pass path to a blocking thread, and NamedTempFile is not easily shared if we need path + handle.
            // Better: Stream to the file handle async.
            
            // Re-create tempfile in a way we use it.
            let async_file = tokio::fs::File::from_std(std_file.try_clone().unwrap());
            let mut async_file = tokio::io::BufWriter::with_capacity(UPLOAD_BUFFER_BYTES, async_file);
            
            // Stream upload to disk
            while let Ok(Some(chunk)) = field.chunk().await {
                 use tokio::io::AsyncWriteExt;
                 if let Err(e) = async_file.write_all(&chunk).await {
                     return (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("Write error: {}", e)).into_response();
                 }
            }
            drop(async_file);
            
            let ext = if format.eq_ignore_ascii_case("text") { "txt" } else { "xml" };
            let meta = translator::extract_output_meta(&temp_path).unwrap_or_else(|_| models::OutputMeta::empty());
            let output_name = build_output_file_name(&original_name, &meta, ext);

            // 2. Output Channel for Streaming XML
            let (tx_out, rx_out) = tokio::sync::mpsc::channel(16);
            
            // 3. Spawn Blocking Translator Task
            let process_path = temp_path.clone();
            let thread_filename = original_name.clone();
            let thread_format = format.clone();

            tokio::task::spawn_blocking(move || {
                let writer = stream_utils::ChannelWriter::new(tx_out);
                let mut buf_writer = BufWriter::with_capacity(64 * 1024, writer);
                
                let res = if thread_format.eq_ignore_ascii_case("text") {
                     text_translator::process_stdf_to_text(&process_path, &thread_filename, &mut buf_writer)
                } else {
                     translator::process_stdf_stream(&process_path, &thread_filename, &mut buf_writer)
                };

                if let Err(e) = res {
                    tracing::error!("Streaming translation failed: {}", e);
                }
                // Attempt cleanup
                let _ = std::fs::remove_file(process_path);
            });
            
            // 4. Create Response Stream
            let stream = tokio_stream::wrappers::ReceiverStream::new(rx_out);
            let body = Body::from_stream(stream);
            
            let content_type = if format.eq_ignore_ascii_case("text") { "text/plain" } else { "application/xml" };

            return Response::builder()
                .header(axum::http::header::CONTENT_TYPE, content_type)
                .header(
                    axum::http::header::CONTENT_DISPOSITION,
                    format!("attachment; filename=\"{}\"", output_name),
                )
                .body(body)
                .unwrap();
        }
    }
    (axum::http::StatusCode::BAD_REQUEST, "No file found").into_response()
}

async fn ensure_upload_dir(folder_hint: Option<String>, allow_existing: bool) -> Result<(PathBuf, String), Response> {
    if let Err(e) = tokio::fs::create_dir_all(UPLOAD_ROOT).await {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Upload root error: {}", e)).into_response());
    }

    let hint = folder_hint.unwrap_or_default();
    let base = sanitize_folder_name(&hint);
    let base_name = if base.is_empty() {
        format!("batch-{}", now_ms())
    } else {
        base
    };

    if allow_existing && !base_name.is_empty() {
        let dir = Path::new(UPLOAD_ROOT).join(&base_name);
        if dir.exists() {
            return Ok((dir, base_name));
        }
    }

    let mut candidate = base_name.clone();
    let mut counter = 1u32;
    loop {
        let dir = Path::new(UPLOAD_ROOT).join(&candidate);
        if !dir.exists() {
            if let Err(e) = tokio::fs::create_dir_all(&dir).await {
                return Err((StatusCode::INTERNAL_SERVER_ERROR, format!("Upload folder error: {}", e)).into_response());
            }
            return Ok((dir, candidate));
        }
        candidate = format!("{}-{}", base_name, counter);
        counter += 1;
    }
}

async fn list_upload_files(upload_dir: &Path) -> Result<Vec<UploadFileInfo>, String> {
    let mut entries = tokio::fs::read_dir(upload_dir)
        .await
        .map_err(|e| format!("List upload error: {}", e))?;
    let mut files = Vec::new();

    while let Some(entry) = entries.next_entry().await.map_err(|e| format!("List upload error: {}", e))? {
        let file_type = entry.file_type().await.map_err(|e| format!("List upload error: {}", e))?;
        if !file_type.is_file() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        let size_bytes = entry.metadata().await.map(|m| m.len()).unwrap_or(0);
        files.push(UploadFileInfo { name, size_bytes });
    }

    files.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(files)
}

async fn load_chunk_state(path: &Path, params: &ChunkUploadQuery) -> Result<ChunkState, String> {
    if path.exists() {
        let bytes = tokio::fs::read(path).await.map_err(|e| format!("Chunk state read error: {}", e))?;
        let state: ChunkState = serde_json::from_slice(&bytes).map_err(|e| format!("Chunk state parse error: {}", e))?;
        if state.total_chunks != params.total_chunks
            || state.total_size != params.total_size
            || state.chunk_size != params.chunk_size
        {
            return Err("Chunk metadata mismatch".to_string());
        }
        return Ok(state);
    }

    Ok(ChunkState {
        total_chunks: params.total_chunks,
        total_size: params.total_size,
        chunk_size: params.chunk_size,
        received: vec![0; params.total_chunks as usize],
    })
}

async fn save_chunk_state(path: &Path, state: &ChunkState) -> Result<(), String> {
    let bytes = serde_json::to_vec(state).map_err(|e| format!("Chunk state serialize error: {}", e))?;
    tokio::fs::write(path, bytes)
        .await
        .map_err(|e| format!("Chunk state write error: {}", e))
}

fn expand_input_path(path: &Path, temp_root: &Path) -> Result<Vec<PathBuf>, String> {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    if ext == "gz" {
        return expand_gz(path, temp_root).map(|p| vec![p]);
    }
    if ext == "zip" {
        return expand_zip(path, temp_root);
    }

    if ext.is_empty() {
        if is_gzip_file(path) {
            return expand_gz(path, temp_root).map(|p| vec![p]);
        }
        return Ok(vec![path.to_path_buf()]);
    }

    // If extension looks like a known STDF extension, accept it
    if is_stdf_file_name(path) {
        return Ok(vec![path.to_path_buf()]);
    }

    // As a fallback, try to detect STDF content regardless of extension by
    // attempting to read STDF metadata. This allows files with non-standard
    // extensions (e.g. "stdf_firms") to be treated as STDF when their
    // contents are valid.
    match translator::extract_output_meta(path) {
        Ok(_) => Ok(vec![path.to_path_buf()]),
        Err(_) => Err("Unsupported file type".to_string()),
    }
}

fn expand_gz(path: &Path, temp_root: &Path) -> Result<PathBuf, String> {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("upload.gz");
    let stem = Path::new(file_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("upload");

    let mut target_name = sanitize_file_name(stem);
    if !is_stdf_name_str(&target_name) {
        target_name = format!("{}.stdf", target_name);
    }

    let target_path = temp_root.join(target_name);
    let input = File::open(path).map_err(|e| format!("GZ open error: {}", e))?;
    let mut decoder = flate2::read::GzDecoder::new(input);
    let mut output = File::create(&target_path).map_err(|e| format!("GZ output error: {}", e))?;
    std::io::copy(&mut decoder, &mut output).map_err(|e| format!("GZ decode error: {}", e))?;
    Ok(target_path)
}

fn expand_zip(path: &Path, temp_root: &Path) -> Result<Vec<PathBuf>, String> {
    let input = File::open(path).map_err(|e| format!("ZIP open error: {}", e))?;
    let mut archive = zip::ZipArchive::new(input).map_err(|e| format!("ZIP read error: {}", e))?;
    let mut extracted = Vec::new();

    for idx in 0..archive.len() {
        let mut entry = archive.by_index(idx).map_err(|e| format!("ZIP entry error: {}", e))?;
        if entry.is_dir() {
            continue;
        }

        // take an owned copy of the entry name so we don't borrow `entry`
        let raw_name = entry.name().to_string();
        let base_name = Path::new(&raw_name)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("entry.stdf");

        let mut safe_name = sanitize_file_name(base_name);
        let ext = Path::new(base_name)
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();

        if ext.is_empty() {
            if !is_stdf_name_str(&safe_name) {
                safe_name = format!("{}.stdf", safe_name);
            }
            let target_path = temp_root.join(safe_name);
            let mut output = File::create(&target_path).map_err(|e| format!("ZIP output error: {}", e))?;
            std::io::copy(&mut entry, &mut output).map_err(|e| format!("ZIP extract error: {}", e))?;
            if is_gzip_file(&target_path) {
                let expanded = expand_gz(&target_path, temp_root)?;
                let _ = std::fs::remove_file(&target_path);
                extracted.push(expanded);
            } else {
                extracted.push(target_path);
            }
            continue;
        }

        if ext == "gz" {
            let target_path = temp_root.join(safe_name);
            let mut output = File::create(&target_path).map_err(|e| format!("ZIP output error: {}", e))?;
            std::io::copy(&mut entry, &mut output).map_err(|e| format!("ZIP extract error: {}", e))?;
            let expanded = expand_gz(&target_path, temp_root)?;
            extracted.push(expanded);
            continue;
        }

        // Extract the entry to a temp file and then detect its type by content
        let target_path = temp_root.join(safe_name);
        let mut output = File::create(&target_path).map_err(|e| format!("ZIP output error: {}", e))?;
        std::io::copy(&mut entry, &mut output).map_err(|e| format!("ZIP extract error: {}", e))?;

        // If the extracted file is a gzip stream, expand it
        if is_gzip_file(&target_path) {
            let expanded = expand_gz(&target_path, temp_root)?;
            let _ = std::fs::remove_file(&target_path);
            extracted.push(expanded);
            continue;
        }

        // If filename extension indicates STDF, accept it
        if is_stdf_name_str(base_name) {
            extracted.push(target_path);
            continue;
        }

        // Fallback: try to detect STDF by attempting to read STDF metadata
        if translator::extract_output_meta(&target_path).is_ok() {
            extracted.push(target_path);
            continue;
        }

        // Not an STDF file — remove the temp and skip
        let _ = std::fs::remove_file(&target_path);
    }

    if extracted.is_empty() {
        return Err("ZIP archive had no STDF files".to_string());
    }

    Ok(extracted)
}

fn is_stdf_file_name(path: &Path) -> bool {
    path.extension()
        .and_then(|s| s.to_str())
        .map(|ext| {
            let ext = ext.to_ascii_lowercase();
            ext == "stdf" || ext == "std"
        })
        .unwrap_or(false)
}

fn is_stdf_name_str(name: &str) -> bool {
    Path::new(name)
        .extension()
        .and_then(|s| s.to_str())
        .map(|ext| {
            let ext = ext.to_ascii_lowercase();
            ext == "stdf" || ext == "std"
        })
        .unwrap_or(false)
}

fn is_gzip_file(path: &Path) -> bool {
    let mut file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return false,
    };
    let mut header = [0u8; 2];
    use std::io::Read;
    if let Err(_) = file.read_exact(&mut header) {
        return false;
    }
    header == [0x1f, 0x8b]
}

fn sanitize_folder_name(input: &str) -> String {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let sanitized: String = trimmed
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    sanitized.trim_matches('_').to_string()
}

fn sanitize_file_name(input: &str) -> String {
    let base = Path::new(input)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("file.stdf");
    let mut sanitized: String = base
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' { c } else { '_' })
        .collect();
    if sanitized.is_empty() {
        sanitized = format!("file-{}.stdf", now_ms());
    }
    sanitized
}

fn sanitize_token(input: &str) -> String {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let sanitized: String = trimmed
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    sanitized.trim_matches('_').to_string()
}

fn build_output_file_name(original_name: &str, meta: &models::OutputMeta, ext: &str) -> String {
    let stem = Path::new(original_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("output");
    let tester = sanitize_token(&meta.tester);
    let platform = sanitize_token(&meta.platform);
    let session = sanitize_token(&meta.session);
    let stem = sanitize_token(stem);

    let tester = if tester.is_empty() { "unknown" } else { tester.as_str() };
    let platform = if platform.is_empty() { "unknown" } else { platform.as_str() };
    let session = if session.is_empty() { "unknown" } else { session.as_str() };
    let stem = if stem.is_empty() { "output" } else { stem.as_str() };

    format!("{}_{}_{}_{}.{}", tester, platform, session, stem, ext)
}

fn unique_output_path(dir: &Path, base_name: &str) -> (PathBuf, String) {
    let mut candidate = base_name.to_string();
    let mut counter = 1u32;
    loop {
        let path = dir.join(&candidate);
        if !path.exists() {
            return (path, candidate);
        }
        candidate = add_suffix(base_name, counter);
        counter += 1;
    }
}

fn add_suffix(base_name: &str, counter: u32) -> String {
    if let Some((name, ext)) = base_name.rsplit_once('.') {
        format!("{}-{}.{}", name, counter, ext)
    } else {
        format!("{}-{}", base_name, counter)
    }
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn format_duration(d: std::time::Duration) -> String {
    let total_ms = d.as_millis();
    let hours = total_ms / 3_600_000;
    let minutes = (total_ms % 3_600_000) / 60_000;
    let seconds = (total_ms % 60_000) / 1000;
    let millis = total_ms % 1000;
    if hours > 0 {
        format!("{}h {:02}m {:02}.{:03}s", hours, minutes, seconds, millis)
    } else if minutes > 0 {
        format!("{}m {:02}.{:03}s", minutes, seconds, millis)
    } else {
        format!("{}.{:03}s", seconds, millis)
    }
}

fn send_event(tx: &tokio::sync::mpsc::Sender<Bytes>, payload: serde_json::Value) {
    let line = format!("data: {}\n\n", payload.to_string());
    let _ = tx.blocking_send(Bytes::from(line));
}

fn content_type_for_file(name: &str) -> &'static str {
    let ext = Path::new(name)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    match ext.as_str() {
        "xml" => "application/xml",
        "txt" => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn expand_zip_accepts_extensionless_entries() {
        let temp_dir = tempfile::TempDir::new().expect("temp dir");
        let zip_path = temp_dir.path().join("sample.zip");

        {
            let file = File::create(&zip_path).expect("zip create");
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::FileOptions::default();
            zip.start_file("noext", options).expect("start file");
            zip.write_all(b"STDF").expect("write entry");
            zip.finish().expect("finish zip");
        }

        let out_dir = temp_dir.path().join("out");
        std::fs::create_dir_all(&out_dir).expect("out dir");
        let extracted = expand_zip(&zip_path, &out_dir).expect("expand zip");

        assert_eq!(extracted.len(), 1);
        let extracted_path = &extracted[0];
        assert_eq!(
            extracted_path.extension().and_then(|s| s.to_str()).unwrap_or(""),
            "stdf"
        );
        assert!(extracted_path.exists());
    }

    #[test]
    fn expand_zip_accepts_gz_entries() {
        let temp_dir = tempfile::TempDir::new().expect("temp dir");
        let zip_path = temp_dir.path().join("sample-gz.zip");

        let mut gz_bytes = Vec::new();
        {
            let mut encoder = flate2::write::GzEncoder::new(&mut gz_bytes, flate2::Compression::default());
            encoder.write_all(b"STDF").expect("gz write");
            encoder.finish().expect("gz finish");
        }

        {
            let file = File::create(&zip_path).expect("zip create");
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::FileOptions::default();
            zip.start_file("sample.stdf.gz", options).expect("start file");
            zip.write_all(&gz_bytes).expect("write entry");
            zip.finish().expect("finish zip");
        }

        let out_dir = temp_dir.path().join("out");
        std::fs::create_dir_all(&out_dir).expect("out dir");
        let extracted = expand_zip(&zip_path, &out_dir).expect("expand zip");

        assert_eq!(extracted.len(), 1);
        let extracted_path = &extracted[0];
        assert_eq!(
            extracted_path.extension().and_then(|s| s.to_str()).unwrap_or(""),
            "stdf"
        );
        assert!(extracted_path.exists());
    }

    #[test]
    fn expand_zip_accepts_gz_entries_without_extension() {
        let temp_dir = tempfile::TempDir::new().expect("temp dir");
        let zip_path = temp_dir.path().join("sample-gz-noext.zip");

        let mut gz_bytes = Vec::new();
        {
            let mut encoder = flate2::write::GzEncoder::new(&mut gz_bytes, flate2::Compression::default());
            encoder.write_all(b"STDF").expect("gz write");
            encoder.finish().expect("gz finish");
        }

        {
            let file = File::create(&zip_path).expect("zip create");
            let mut zip = zip::ZipWriter::new(file);
            let options = zip::write::FileOptions::default();
            zip.start_file("sample", options).expect("start file");
            zip.write_all(&gz_bytes).expect("write entry");
            zip.finish().expect("finish zip");
        }

        let out_dir = temp_dir.path().join("out");
        std::fs::create_dir_all(&out_dir).expect("out dir");
        let extracted = expand_zip(&zip_path, &out_dir).expect("expand zip");

        assert_eq!(extracted.len(), 1);
        let extracted_path = &extracted[0];
        assert_eq!(
            extracted_path.extension().and_then(|s| s.to_str()).unwrap_or(""),
            "stdf"
        );
        assert!(extracted_path.exists());
    }

    #[test]
    fn expand_input_path_accepts_extensionless_gz() {
        let temp_dir = tempfile::TempDir::new().expect("temp dir");
        let temp_root = temp_dir.path().join("out");
        std::fs::create_dir_all(&temp_root).expect("out dir");
        let raw_path = temp_dir.path().join("payload");

        {
            let file = File::create(&raw_path).expect("file create");
            let mut encoder = flate2::write::GzEncoder::new(file, flate2::Compression::default());
            encoder.write_all(b"STDF").expect("gz write");
            encoder.finish().expect("gz finish");
        }

        let extracted = expand_input_path(&raw_path, &temp_root).expect("expand input");
        assert_eq!(extracted.len(), 1);
        let extracted_path = &extracted[0];
        assert_eq!(
            extracted_path.extension().and_then(|s| s.to_str()).unwrap_or(""),
            "stdf"
        );
        assert!(extracted_path.exists());
    }

    #[test]
    fn expand_input_path_accepts_extensionless_raw() {
        let temp_dir = tempfile::TempDir::new().expect("temp dir");
        let temp_root = temp_dir.path().join("out");
        std::fs::create_dir_all(&temp_root).expect("out dir");
        let raw_path = temp_dir.path().join("payload");

        std::fs::write(&raw_path, b"STDF").expect("write raw");

        let extracted = expand_input_path(&raw_path, &temp_root).expect("expand input");
        assert_eq!(extracted.len(), 1);
        assert_eq!(extracted[0], raw_path);
        assert!(extracted[0].exists());
    }
}
