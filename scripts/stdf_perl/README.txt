Using STDF PERL:

- Untar stdf_perl.tar.gz into a directory such as stdf_perl
- Set PERL5LIB environment variable to full path to lib directory.
- After setting PERL5LIB the scripts will work even if the script directory is
  not in PATH.

scripts/stdf_copy input-stdf-file output-ascii-file
  -- Reads input-stdf-file and writes to output-ascii-file.
  -- Can substitute a dash '-' for output-ascii-file to output to stdout.

scripts/stdf_copy_ascii input-ascii-file output-stdf-file
  -- Reads input-ascii-file and writes to output-stdf-file
  -- File must conform to the ASCII formatting of stdf_copy's
output-ascii-file to read the ASCII file correctly.
