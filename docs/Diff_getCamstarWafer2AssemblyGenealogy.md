# Diff: getCamstarWafer2AssemblyGenealogy.pl → n_getCamstarWafer2AssemblyGenealogy.pl

This document highlights the important code differences between
`scripts/getCamstarWafer2AssemblyGenealogy.pl` (original) and
`scripts/n_getCamstarWafer2AssemblyGenealogy.pl` (enhanced).

Summary of changes
* Added run locking to prevent concurrent runs (`--LOCK_FILE`, `flock`).
* Added JSONL benchmarking logging (`--BENCHMARK_LOG`, `writeBenchmark()`).
* Added start/end timing and elapsed formatting (`Time::HiRes`, `formatElapsed`).
* Extended CLI to include Snowflake-related options (`--SOURCE_WAREHOUSE`, `--SOURCE_SCHEMA`) and pipeline metadata.
* `getFabCodes()` updated to query Snowflake via ODBC when `SOURCE_SCHEMA`/`SOURCE_WAREHOUSE` provided; original version used Oracle `DWPRD`.
* Extra modules imported for benchmarking, locking and path handling (`File::Spec`, `Time::HiRes`, `JSON::PP`, `Fcntl`).
* Metadata collection of output files/rowcounts to include in benchmark payload.

Representative diffs (key hunks)

1) CLI options and defaults

ORIGINAL (getCamstarWafer2AssemblyGenealogy.pl)
```
my %hOptions = (
   "SOURCE_DB"     => undef,
   "LOGFILE"       => undef,
   "OUT_GEN"       => undef,
   "OUT_TRACE"     => undef,
   "ARCHIVE_GEN"   => undef,
   "START_HOURS"   => undef,
   "END_HOURS"     => undef,
   "ARCHIVE_GEN"   => undef,
   "ARCHIVE_TRACE" => undef
);

unless (GetOptions( \%hOptions, "SOURCE_DB=s", "START_HOURS=s", "END_HOURS=s", "OUT_GEN=s", "OUT_TRACE=s", "ARCHIVE_GEN=s", "ARCHIVE_TRACE=s", "LOGFILE=s")){
    print($usageMsg);
    dpExit( 1, "invalid options" );
}
```

ENHANCED (n_getCamstarWafer2AssemblyGenealogy.pl)
```
my %hOptions = (
  "SOURCE_DB"     => undef,
  "SOURCE_WAREHOUSE" => undef,
  "LOGFILE"       => undef,
  "BENCHMARK_LOG" => undef,
  "BENCHMARK_INCLUDE_NON_ARCHIVE" => undef,
  "LOCK_FILE"     => undef,
  "PIPELINE_NAME" => undef,
  "PIPELINE_TYPE" => undef,
  "OUT_GEN"       => undef,
  "OUT_TRACE"     => undef,
  "ARCHIVE_GEN"   => undef,
  "START_HOURS"   => undef,
  "END_HOURS"     => undef,
  "ARCHIVE_GEN"   => undef,
  "ARCHIVE_TRACE" => undef
);

unless (GetOptions( \%hOptions, "SOURCE_DB=s","SOURCE_WAREHOUSE=s","SOURCE_SCHEMA=s", "START_HOURS=s", "END_HOURS=s", "OUT_GEN=s", "OUT_TRACE=s", "ARCHIVE_GEN=s", "ARCHIVE_TRACE=s", "LOGFILE=s", "BENCHMARK_LOG=s", "BENCHMARK_INCLUDE_NON_ARCHIVE!", "LOCK_FILE=s", "PIPELINE_NAME=s", "PIPELINE_TYPE=s")){
    print($usageMsg);
    dpExit( 1, "invalid options" );
}
```

2) Imports / new modules

ORIGINAL import excerpt
```
use File::Basename qw/basename/;
use DateTime::Format::Strptime;
use Carp;
use PDF::Log;
use PDF::DAO;
use PDF::DpData;
use PDF::DpLoad;
use PDF::WS;
use IO::Compress::Gzip qw(gzip $GzipError) ;;
use Data::Dumper;
```

ENHANCED import excerpt
```
use File::Basename qw/basename dirname/;
use File::Spec;
use DateTime::Format::Strptime;
use Carp;
use PDF::Log;
use PDF::DAO;
use PDF::DpData;
use PDF::DpLoad;
use PDF::WS;
use IO::Compress::Gzip qw(gzip $GzipError) ;;
use Data::Dumper;
use Time::HiRes qw(time);
use JSON::PP;
use Fcntl qw(:flock);
```

3) Locking and benchmark timing (added near script start)

ENHANCED snippet (added)
```
my $startTime = time();
my $startLocal = DateTime->now(time_zone => 'local')->strftime('%Y-%m-%d %H:%M:%S');
my $startUtc = DateTime->now(time_zone => 'UTC')->strftime('%Y-%m-%dT%H:%M:%SZ');

my $lockFile = $hOptions{LOCK_FILE};
if (!defined($lockFile) || $lockFile eq "")
{
  $lockFile = "./log/n_getCamstarWafer2AssemblyGenealogy.lock";
}
my $lockDir = dirname($lockFile);
if (defined($lockDir) && length($lockDir) > 0 && !-d $lockDir)
{
  mkdir($lockDir);
}
open(my $lockFH, ">>", $lockFile) or dpExit(1, "Unable to open lock file $lockFile: $!");
unless (flock($lockFH, LOCK_EX|LOCK_NB))
{
  dpExit(1, "Another instance is already running (lock: $lockFile)");
}
```

4) Fab-code lookup: Oracle → Snowflake-aware

ORIGINAL `getFabCodes()`
```
sub getFabCodes() {
  my %fabCodes;
  my $dbhDWPRD = DBI->connect("dbi:Oracle:DWPRD", "BIW_EXENSIO_READ", $ENV{DW_PASS});
  ... query BIWMARTS.SITE_DIM ...
  return %fabCodes;
}
```

ENHANCED `getFabCodes()`
```
sub getFabCodes {
  my %fabCodes;
  my $snowUser = $ENV{SNOW_USER} || $ENV{SNOWFLAKE_USER} || "MFG_PRD_RPT_EXENSIO_USER";
  my $snowPass = $ENV{SNOW_PASSWORD} || $ENV{SNOW_PASS} || $ENV{SNOWFLAKE_PASSWORD} || "";
  my $snowSid  = $ENV{SNOW_SID} || $ENV{SNOWFLAKE_DSN} || "MART_SNOWFLAKE";
  my $dbh = DBI->connect("dbi:ODBC:$snowSid", $snowUser, $snowPass);
  my $schema = $hOptions{SOURCE_SCHEMA};
  my $siteDimTable = "ANALYTICSPRD.ENTERPRISE.SITE_DIM";
  if ($schema =~ /^(\w+)\./) { ... adjust $siteDimTable ... }
  $dbh->do("use warehouse $hOptions{SOURCE_WAREHOUSE};");
  ... query $siteDimTable ...
  return %fabCodes;
}
```

5) Benchmark write and helpers (added)

ENHANCED added functions
```
sub writeBenchmark() { ... }
sub formatElapsed() { ... }
sub normalizeBenchmarkPath() { ... }
```

6) Benchmark payload and invocation (after outputs written)

ENHANCED snippet (added)
```
if (defined($hOptions{BENCHMARK_LOG}) && length($hOptions{BENCHMARK_LOG}) > 0)
{
  my %stats = (
    start_local => $startLocal,
    end_local => $endLocal,
    elapsed_seconds => sprintf("%.3f", $elapsed),
    rowcount => $genRowsWritten + $traceRowsWritten,
    archived_gen_files => [ $genArchFile ],
    archived_trace_files => \@traceArchFiles,
    ...
  );
  writeBenchmark($hOptions{BENCHMARK_LOG}, \%stats);
}
```

Notes
* The enhanced script retains core data-processing logic (SQL composition, main loop, LOTG fallback, wafer ID normalization, output format), so behavioral differences are additive (locking, telemetry, Snowflake fab lookup).
* I did not modify `scripts/getCamstarWafer2AssemblyGenealogy.pl` — this doc only captures differences.

If you want an exact, line-by-line unified diff file (`git diff`-style) I can generate and save it under `docs/` as well; tell me whether you prefer a full unified patch or the concise summary above.
