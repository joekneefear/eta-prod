# Quick Start Guide for Linux Systems

## For the dpower User on Linux

### Step 1: Set Up Rust (One-Time Setup)

If Rust is not already installed:

```bash
# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Reload shell environment
source $HOME/.cargo/env

# Verify installation
rustc --version
cargo --version
```

### Step 2: Configure Cargo to Use User Home Directory

This solves the permission issues with `/usr/local/cargo/`:

```bash
# Create user Cargo directory
mkdir -p ~/.cargo

# Set CARGO_HOME environment variable permanently
echo 'export CARGO_HOME=$HOME/.cargo' >> ~/.bashrc
echo 'export CARGO_HOME=$HOME/.cargo' >> ~/.bash_profile

# Apply changes immediately
export CARGO_HOME=$HOME/.cargo

# Verify
echo $CARGO_HOME
```

### Step 3: Clone/Download the Translator

```bash
# Navigate to working directory
cd /export/home/dpower/jag

# If cloning from repository:
# git clone <repo-url> stdf_translator
# cd stdf_translator

# OR if you have the source files already:
cd stdf_translator
```

### Step 4: Build the Project

```bash
# Clean any previous builds
cargo clean

# Build in release mode (optimized)
cargo build --release

# This will take 3-5 minutes on first build
# Subsequent builds are much faster
```

### Step 5: Convert Your STDF File

```bash
# CLI mode - convert file to XML
cargo run --release -- \
  --input 0c4th001_G520271A09_ft1_150_tst_Carmona_1_20260125221848.stdf_firms_20260127_052810 \
  --output 5gbTest.xml

# Check the output
ls -lh 5gbTest.xml
cat 5gbTest.xml | head -50  # View first 50 lines
```

### Step 6 (Optional): Run as Web Service

```bash
# Start the web server
cargo run --release -- --server

# The server will listen on http://localhost:3000
# You can then use curl to convert files:
# 
# curl -X POST -F "file=@input.stdf" http://localhost:3000/convert -o output.xml

# To stop the server: Press Ctrl+C
```

## Permanent Installation (Optional)

To use the translator without navigating to the directory:

```bash
# Build the binary
cargo build --release

# Copy to a directory in PATH (or add project to PATH)
cp target/release/stdf_translator ~/.local/bin/

# Or add to PATH
export PATH="$PATH:$(pwd)/target/release"
echo 'export PATH="$PATH:/export/home/dpower/jag/stdf_translator/target/release"' >> ~/.bashrc

# Now you can run from anywhere:
stdf_translator --input file.stdf --output file.xml
```

## Troubleshooting on Linux

### Issue: Permission denied on Cargo cache

**If you still get permission errors:**

```bash
# Clean the problematic cache
rm -rf ~/.cargo/registry/cache

# Or clean everything and rebuild
rm -rf ~/.cargo/registry
rm -rf ~/.cargo/git
cargo clean

# Try building again
cargo build --release
```

### Issue: Command not found: cargo

**Solution:**
```bash
# Make sure Rust is in your PATH
source ~/.cargo/env

# Or add permanently to ~/.bashrc
echo 'source $HOME/.cargo/env' >> ~/.bashrc
source ~/.bashrc
```

### Issue: "target not found" during build

**Solution:**
```bash
# Download dependencies and build
cargo build --release -vv  # -vv for verbose output to see progress
```

## Using the Translator

### CLI Usage

```bash
# Basic conversion
cargo run --release -- --input input.stdf --output output.xml

# Help and options
cargo run --release -- --help

# Output:
# Usage: stdf_translator [OPTIONS]
# 
# Options:
#   -s, --server              Start the web server
#   -i, --input <INPUT>       Input STDF file for CLI mode
#   -o, --output <OUTPUT>     Output file for CLI mode
#   -f, --format <FORMAT>     Output format: xml or text [default: xml]
#   -h, --help                Print help
#   -V, --version             Print version
```

### Working with Large Files

The translator is optimized for large files:

```bash
# For files over 500MB, use explicit timeout if needed
timeout 600 cargo run --release -- --input large.stdf --output large.xml

# Monitor progress with tail
tail -f large.xml  # In another terminal

# Monitor memory usage
watch -n 1 'ps aux | grep stdf_translator'
```

## Output Format

The output is valid XML matching the SXML format used by the Java encoder:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Xml>
  <File FileName="..." CPUType="2" STDFVersion="4">
    <Audits>...</Audits>      <!-- Only if ATR records exist -->
    <Lot ...>
      <Sites>...</Sites>      <!-- Only if GDR records exist -->
      <Pins>...</Pins>        <!-- Only if GDR records exist -->
      <Wafers>
        <Wafer ...>
          <Units>
            <Unit ...>
              <Test .../>     <!-- Test results -->
              <Result .../>   <!-- Unit result -->
            </Unit>
          </Units>
        </Wafer>
      </Wafers>
    </Lot>
  </File>
</Xml>
```

## Validating Output

```bash
# Check XML is well-formed
xmllint --noout output.xml

# Pretty-print the XML
xmllint --format output.xml | head -50

# Count elements
xmllint --xpath 'count(//Test)' output.xml

# Check file size
du -h output.xml
wc -l output.xml  # Line count
```

## Performance Tips

1. **SSD Storage**: Place both input and output on SSD for best performance
2. **Memory**: No special memory considerations; translator is memory-efficient
3. **CPU**: Single-threaded; will use one core
4. **Network**: Web service uses minimal bandwidth

## Examples

### Example 1: Basic Conversion

```bash
cd /export/home/dpower/jag/stdf_translator
cargo run --release -- \
  --input samples/test.stdf \
  --output output.xml
```

### Example 2: Batch Processing

```bash
#!/bin/bash
# Convert all .stdf files in a directory

cd /export/home/dpower/jag/stdf_translator

for file in *.stdf; do
    output="${file%.stdf}.xml"
    echo "Converting $file to $output..."
    cargo run --release -- --input "$file" --output "$output"
done

echo "Done! Check for .xml files"
```

### Example 3: Using with Python Script

```python
#!/usr/bin/env python3
import subprocess
import sys

stdf_file = sys.argv[1] if len(sys.argv) > 1 else "input.stdf"
xml_file = stdf_file.replace('.stdf', '.xml')

# Run the translator
result = subprocess.run([
    'cargo', 'run', '--release', '--',
    '--input', stdf_file,
    '--output', xml_file
], cwd='/export/home/dpower/jag/stdf_translator')

if result.returncode == 0:
    print(f"✓ Successfully converted {stdf_file} to {xml_file}")
else:
    print(f"✗ Conversion failed with code {result.returncode}")
    sys.exit(1)
```

### Example 4: Using as a Service (systemd)

```bash
# Create a systemd service file
sudo tee /etc/systemd/system/stdf-translator.service <<EOF
[Unit]
Description=STDF to XML Translator Service
After=network.target

[Service]
Type=simple
User=dpower
WorkingDirectory=/export/home/dpower/jag/stdf_translator
ExecStart=/export/home/dpower/.cargo/bin/cargo run --release -- --server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl enable stdf-translator
sudo systemctl start stdf-translator

# Check status
sudo systemctl status stdf-translator

# View logs
sudo journalctl -u stdf-translator -f
```

## Getting Help

1. **Check logs**: Run with verbose output
   ```bash
   cargo run --release -- --input file.stdf --output file.xml 2>&1 | tee conversion.log
   ```

2. **Verify build**: Test the build is working
   ```bash
   cargo test --release
   ```

3. **Check STDF file**: Ensure the input file is valid
   ```bash
   file input.stdf
   head -c 1000 input.stdf | od -c | head  # Hex dump
   ```

4. **Review output**: Validate generated XML
   ```bash
   xmllint --noout --schema schema.xsd output.xml
   ```

---

**For questions or issues**, refer to:
- Main documentation: `docs/SXML_FORMAT_GUIDE.md`
- Enhancement summary: `ENHANCEMENT_SUMMARY.md`
- Enhanced README: `README_ENHANCED.md`

