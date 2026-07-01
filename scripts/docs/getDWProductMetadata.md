santizie field values, remove qoutes single or double from the value

Adding a sed step to remove single and double quotes from the output file.
n_getDWProductMetadata.sh
+3
if [ -f "${outFileTmp}" ]; then
# Sanitize field values: remove single and double quotes from outputsed -i "s/[\"']//g" "${outFileTmp}"if [ -f "${outFileTmp}" ]; then
Summary of the change:
Sanitization step
After the header is added, the script runs:
sed -i "s/[\"']//g" "${outFileTmp}"
That removes every double quote (") and single quote (') in the output file (header and data).
So any quotes coming from Snowflake in the pipe‑delimited fields are stripped before the file is archived or moved to the final output path.
now for 
n_getDWProductMetadata.sh
 update to log to benchmar logging similar to 
n_getCamstarWafer2AssemblyGenealogy.pl
 if production default bencmark loggin to /apps/exensio_data/reference_data/benchmark/benchmark.jsonl and if --test  -> /export/home/dpower/jag/test_refdata/benchmark/benchmark.jsonl file.  -> this is the class what the jsonl file fields should have -> 
models.py (5-34)
  in this case we dont have multi files to we wwill jut have the output file, archived_file, log_file in terms of file logging. assumption others info should be logged by default which not files related

Checking how the Perl script performs benchmark logging:
n_getDWProductMetadata.sh
+3
# 11-Feb-26 jgarcia - Snowflake only: removed Oracle path; only --test option; Snowflake credentials from env only.PRODUCTION_ARCHIVE_DIR=/apps/exensio_data/archives-yms/reference_data/product
# 11-Feb-26 jgarcia - Snowflake only: removed Oracle path; only --test option; Snowflake credentials from env only.# 11-Feb-26 jgarcia - Benchmark JSONL logging (PipelineInfo fields); production and --test paths.PRODUCTION_ARCHIVE_DIR=/apps/exensio_data/archives-yms/reference_data/productBENCHMARK_LOG_PRODUCTION=/apps/exensio_data/reference_data/benchmark/benchmark.jsonl
n_getDWProductMetadata.sh
+4
  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$TEST_REFDATA_ARCHIVE_PATH}"else  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$PRODUCTION_ARCHIVE_DIR}"
  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$TEST_REFDATA_ARCHIVE_PATH}"  benchmark_log="$BENCHMARK_LOG_TEST"  benchmark_env="test"else  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$PRODUCTION_ARCHIVE_DIR}"
n_getDWProductMetadata.sh
+5
# Benchmark: capture start time (PipelineInfo fields)start_epoch=$(date +%s.%3N)start_local=$(date +"%Y-%m-%d %H:%M:%S")start_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
n_getDWProductMetadata.sh
+54
if [ -f "${outFileTmp}" ]; then    gzip -f "${archiveDir}/${b_name}"
archived_file_path=""if [ -f "${outFileTmp}" ]; then    gzip -f "${archiveDir}/${b_name}"    archived_file_path="${archiveDir}/${b_name}.gz"
Making elapsed_seconds calculation portable (avoid relying on bc):
n_getDWProductMetadata.sh
+1
-1
  end_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")  elapsed_seconds=$(echo "$end_epoch - $start_epoch" | bc)  elapsed_sec_int=$(echo "$elapsed_seconds" | cut -d. -f1)
  elapsed_seconds=$(echo "$end_epoch - $start_epoch" | bc)  end_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")  elapsed_seconds=$(awk "BEGIN { printf \"%.3f\", $end_epoch - $start_epoch }")  elapsed_sec_int=$(echo "$elapsed_seconds" | cut -d. -f1)
Verifying the benchmark block and that the Python one-liner emits a single line:
n_getDWProductMetadata.sh
+1
-1
# Benchmark: capture start time (PipelineInfo fields)start_epoch=$(date +%s.%3N)start_local=$(date +"%Y-%m-%d %H:%M:%S")
start_epoch=$(date +%s.%3N)# Benchmark: capture start time (PipelineInfo fields)start_epoch=$(date +%s)start_local=$(date +"%Y-%m-%d %H:%M:%S")
n_getDWProductMetadata.sh
+3
-3
if [ -n "${benchmark_log:-}" ]; then  end_epoch=$(date +%s.%3N)  end_local=$(date +"%Y-%m-%d %H:%M:%S")  end_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")  elapsed_seconds=$(awk "BEGIN { printf \"%.3f\", $end_epoch - $start_epoch }")
  end_epoch=$(date +%s.%3N)  elapsed_seconds=$(awk "BEGIN { printf \"%.3f\", $end_epoch - $start_epoch }")  elapsed_sec_int=$(echo "$elapsed_seconds" | cut -d. -f1)if [ -n "${benchmark_log:-}" ]; then  end_epoch=$(date +%s)  end_local=$(date +"%Y-%m-%d %H:%M:%S")  end_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
Summary of what was added:
1. Benchmark log paths
Production: /apps/exensio_data/reference_data/benchmark/benchmark.jsonl
--test: /export/home/dpower/jag/test_refdata/benchmark/benchmark.jsonl
2. When benchmark is written
After a successful run: output moved to outFile, optional archive, then one JSONL record is appended to the benchmark log.
Benchmark directory is created with mkdir -p if it doesn’t exist.
3. PipelineInfo fields written (aligned with models.py)
Required: start_local, end_local, start_utc, end_utc (ISO/local), elapsed_seconds, elapsed_human, output_file, rowcount, log_file, pid, date_code
Optional: pipeline_name ("DWProductMetadata"), script_name (basename of script), pipeline_type ("batch"), environment ("test" when --test, else $ENVIRONMENT or $ENV or "prod"), archived_file (path to the .gz in the archive dir when archiving is done, otherwise omitted)
4. How it’s implemented
Start time is recorded right after dateCode and path setup (before the Snowflake run).
End time, elapsed time, and rowcount (data lines only, header excluded) are computed after moving the output and optional archive.
archived_file_path is set only when archiving runs (archiveDir exists and copy/gzip succeed); that path is written as archived_file in the JSON.
One JSON object per run is printed by Python and appended to the benchmark file (one line per run, JSONL).
If Python or the benchmark write fails, the script still exits 0 (2>/dev/null || true).
5. Environment
With --test, environment is set to "test"; otherwise it uses ENVIRONMENT or ENV if set, else "prod".
can we make the bencmakr logging on/off via options? default is on?

Adding a --no-benchmark option to disable benchmark logging; keeping it on by default.
n_getDWProductMetadata.sh
+10
-6
# 11-Feb-26 jgarcia - Benchmark JSONL logging (PipelineInfo fields); production and --test paths.# Parse --test (or -t) option; production is the default.
# Parse --test (or -t) option; production is the default.# 11-Feb-26 jgarcia - Benchmark JSONL logging (PipelineInfo fields); production and --test paths.# 11-Feb-26 jgarcia - Benchmark logging on/off via --no-benchmark; default is on.
n_getDWProductMetadata.sh
+3
-3
# Paths: --test uses test paths; else REFERENCE_DATA_DIR required.if [ "$use_test_paths" -eq 1 ]; then  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$TEST_REFDATA_ARCHIVE_PATH}"
# Paths: --test uses test paths; else REFERENCE_DATA_DIR required.# Paths: --test uses test paths; else REFERENCE_DATA_DIR required. Benchmark log path when enabled.if [ "$use_test_paths" -eq 1 ]; then  archiveDir="${DW_PRODUCT_METADATA_ARCHIVE_DIR:-$TEST_REFDATA_ARCHIVE_PATH}"
Summary of changes:
1. New option: --no-benchmark
Disables benchmark JSONL logging for that run.
Benchmark logging is on by default when the option is not used.
2. Option parsing
In the same loop as --test/-t, the script now handles --no-benchmark and sets benchmark_enabled=0; otherwise benchmark_enabled stays 1.
3. When benchmark is disabled
benchmark_log is set to empty when --no-benchmark is used, so the existing if [ -n "${benchmark_log:-}" ] block never runs and no JSONL line is written.
4. Usage
Benchmark on (default):
./n_getDWProductMetadata.sh
or
./n_getDWProductMetadata.sh --test
Benchmark off:
./n_getDWProductMetadata.sh --no-benchmark
or
./n_getDWProductMetadata.sh --test --no-benchmark
Usage text was updated to mention --no-benchmark.
should be able to pass pipelinename and pipelinetype as options with current default

n_getDWProductMetadata.sh
+14
-6
benchmark_enabled=1while [ $# -gt 0 ]; do  case "$1" in    --test|-t)     use_test_paths=1; shift ;;
    --test|-t)     use_test_paths=1; shift ;;    --no-benchmark) benchmark_enabled=0; shift ;;benchmark_enabled=1pipeline_name="DWProductMetadata"pipeline_type="batch"while [ $# -gt 0 ]; do  case "$1" in
n_getDWProductMetadata.sh
+2
-2
  BENCHMARK_LOG_FILE="$logFile" BENCHMARK_PID="$$" BENCHMARK_DATE_CODE="$dateCode" \  BENCHMARK_PIPELINE_NAME="DWProductMetadata" BENCHMARK_SCRIPT_NAME="$(basename "$0")" \  BENCHMARK_PIPELINE_TYPE="batch" BENCHMARK_ENV="$benchmark_env" \  BENCHMARK_ARCHIVED_FILE="$archived_file_path" \
  BENCHMARK_PIPELINE_NAME="DWProductMetadata" BENCHMARK_SCRIPT_NAME="$(basename "$0")" \  BENCHMARK_PIPELINE_TYPE="batch" BENCHMARK_ENV="$benchmark_env" \  BENCHMARK_LOG_FILE="$logFile" BENCHMARK_PID="$$" BENCHMARK_DATE_CODE="$dateCode" \  BENCHMARK_PIPELINE_NAME="$pipeline_name" BENCHMARK_SCRIPT_NAME="$(basename "$0")" \  BENCHMARK_PIPELINE_TYPE="$pipeline_type" BENCHMARK_ENV="$benchmark_env" \  BENCHMARK_ARCHIVED_FILE="$archived_file_path" \
Summary of changes:
1. New options
--pipeline_name NAME or --pipeline_name=NAME – value written to benchmark JSONL as pipeline_name. Default: DWProductMetadata.
--pipeline_type TYPE or --pipeline_type=TYPE – value written to benchmark JSONL as pipeline_type. Default: batch.
2. Option parsing
Supports both --opt value and --opt=value.
If --pipeline_name or --pipeline_type is used without a value, the script exits with an error.
3. Usage
Defaults:
./n_getDWProductMetadata.sh
→ benchmark: pipeline_name=DWProductMetadata, pipeline_type=batch.
Override:
./n_getDWProductMetadata.sh --pipeline_name "refdata_dw_product" --pipeline_type "refdata"
or
./n_getDWProductMetadata.sh --pipeline_name=my_pipeline --pipeline_type=streaming
With other options:
./n_getDWProductMetadata.sh --test --pipeline_name DWProductMetadata --pipeline_type batch
(same as default, but explicit.)
Usage text was updated to describe these options.