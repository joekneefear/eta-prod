# Linux Server Deployment Guide

## 1. Get the Binary
You have two options:

### Option A: Build on Server (Recommended if Rust is installed)
1.  **Transfer Source**: Copy the `stdf_translator` folder to your server (e.g., using `scp` or `rsync`).
2.  **Install Rust**: (Skip if installed) `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
3.  **Navigate**: `cd stdf_translator`
4.  **Build**: `cargo build --release`
5.  The binary is at: `target/release/stdf_translator`

### Option B: Build Locally & Copy
If your server doesn't have Rust:
1.  **On your dev machine**: `cargo build --release` (Ensure OS matches, e.g., Linux to Linux. If Windows to Linux, you need cross-compilation).
    *   *Tip*: Using `cross` crate or Docker is easiest for Windows -> Linux.
2.  **Copy**: `scp target/release/stdf_translator user@your-server:/opt/stdf_translator/`

---

## 2. Setup Systemd Service (Auto-restart)
Run the translator as a background service.

1.  **Move Binary**:
    ```bash
    sudo mkdir -p /opt/stdf_translator
    sudo cp target/release/stdf_translator /opt/stdf_translator/
    sudo chmod +x /opt/stdf_translator/stdf_translator
    ```

2.  **Create Service File**:
    Create `/etc/systemd/system/stdf-translator.service`:

    ```ini
    [Unit]
    Description=STDF to XML Translator Service
    After=network.target

    [Service]
    Type=simple
    User=www-data
    WorkingDirectory=/opt/stdf_translator
    ExecStart=/opt/stdf_translator/stdf_translator --server
    Restart=always
    RestartSec=5
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target
    ```

3.  **Start Service**:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable stdf-translator
    sudo systemctl start stdf-translator
    sudo systemctl status stdf-translator
    ```

---

## 3. Configure Nginx
Use the `nginx_stdf.conf` snippet provided in this package.

1.  Copy the location block into your `/etc/nginx/sites-available/default` (or your specific site config).
2.  Test config: `sudo nginx -t`
3.  Reload: `sudo systemctl reload nginx`

## 4. Verify
- **Local**: `curl http://localhost:3000`
- **Public**: Access `http://your-server-ip/stdf-convert/` via browser or API.
