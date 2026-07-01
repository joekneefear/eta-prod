use anyhow::{anyhow, Result};
use clap::Parser;
use reqwest::{Client, Url};
use serde::Deserialize;
use serde_json::json;
use std::collections::HashSet;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about = "Resumable uploader for STDF translator")]
struct Cli {
    /// Base URL for the service (include /stdf-convert-benchmark if behind proxy)
    #[arg(long, default_value = "http://127.0.0.1:3000/stdf-convert-benchmark")]
    base_url: String,

    /// Upload folder name (optional)
    #[arg(long)]
    folder: Option<String>,

    /// Chunk size in MB
    #[arg(long, default_value_t = 16)]
    chunk_size_mb: u64,

    /// Resume from existing chunks if available
    #[arg(long, default_value_t = true)]
    resume: bool,

    /// Files to upload
    #[arg(required = true)]
    files: Vec<PathBuf>,
}

#[derive(Deserialize)]
struct UploadInitResponse {
    upload_id: String,
}

#[derive(Deserialize)]
struct UploadStatusResponse {
    received_chunks: Vec<u32>,
    completed: bool,
}

#[derive(Deserialize)]
struct UploadFileInfo {
    name: String,
    size_bytes: u64,
}

#[derive(Deserialize)]
struct ChunkUploadResponse {
    file: UploadFileInfo,
    complete: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let client = Client::new();
    let base = cli.base_url.trim_end_matches('/').to_string();

    let upload_id = init_upload(&client, &base, cli.folder.as_deref()).await?;
    println!("Upload ID: {}", upload_id);

    for path in cli.files {
        upload_file(&client, &base, &upload_id, &path, cli.chunk_size_mb, cli.resume).await?;
    }

    println!("All uploads complete.");
    Ok(())
}

async fn init_upload(client: &Client, base: &str, folder: Option<&str>) -> Result<String> {
    let url = format!("{}/upload/init", base);
    let payload = json!({
        "folder": folder,
        "allow_existing": true
    });

    let response = client.post(url).json(&payload).send().await?;
    if !response.status().is_success() {
        let text = response.text().await.unwrap_or_default();
        return Err(anyhow!("Init failed: {}", text));
    }

    let data: UploadInitResponse = response.json().await?;
    Ok(data.upload_id)
}

async fn fetch_upload_status(client: &Client, base: &str, upload_id: &str, file_name: &str) -> Result<Option<UploadStatusResponse>> {
    let mut url = Url::parse(&format!("{}/upload/status", base))?;
    url.query_pairs_mut()
        .append_pair("upload_id", upload_id)
        .append_pair("file_name", file_name);

    let response = client.get(url).send().await?;
    if !response.status().is_success() {
        return Ok(None);
    }

    let data: UploadStatusResponse = response.json().await?;
    Ok(Some(data))
}

async fn upload_file(
    client: &Client,
    base: &str,
    upload_id: &str,
    path: &PathBuf,
    chunk_size_mb: u64,
    resume: bool,
) -> Result<()> {
    let file_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| anyhow!("Invalid file name"))?;

    let mut file = File::open(path)?;
    let total_size = file.metadata()?.len();
    let chunk_size = chunk_size_mb * 1024 * 1024;
    if chunk_size == 0 {
        return Err(anyhow!("Chunk size must be > 0"));
    }

    let total_chunks = ((total_size + chunk_size - 1) / chunk_size) as u32;
    if total_chunks == 0 {
        return Err(anyhow!("File size is zero"));
    }

    let mut received = HashSet::new();
    if resume {
        if let Some(status) = fetch_upload_status(client, base, upload_id, file_name).await? {
            if status.completed {
                println!("{} already uploaded.", file_name);
                return Ok(());
            }
            received.extend(status.received_chunks);
        }
    }

    for idx in 0..total_chunks {
        if received.contains(&idx) {
            continue;
        }
        let offset = idx as u64 * chunk_size;
        let remaining = total_size.saturating_sub(offset);
        let read_len = std::cmp::min(chunk_size, remaining) as usize;
        let mut buffer = vec![0u8; read_len];
        file.seek(SeekFrom::Start(offset))?;
        file.read_exact(&mut buffer)?;

        let mut url = Url::parse(&format!("{}/upload/chunk", base))?;
        url.query_pairs_mut()
            .append_pair("upload_id", upload_id)
            .append_pair("file_name", file_name)
            .append_pair("chunk_index", &idx.to_string())
            .append_pair("total_chunks", &total_chunks.to_string())
            .append_pair("chunk_size", &chunk_size.to_string())
            .append_pair("total_size", &total_size.to_string());

        let response = client.post(url).body(buffer).send().await?;
        if !response.status().is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(anyhow!("Chunk upload failed: {}", text));
        }

        let result: ChunkUploadResponse = response.json().await?;
        let pct = ((idx + 1) as f64 / total_chunks as f64) * 100.0;
        println!(
            "{}: {:.1}% ({}/{}) {}",
            file_name,
            pct,
            idx + 1,
            total_chunks,
            if result.complete { "done" } else { "" }
        );
    }

    println!("Uploaded {} ({} bytes)", file_name, total_size);
    Ok(())
}
