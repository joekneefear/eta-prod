#!/bin/bash
# Syntax validation script for Oracle benchmark integration

echo "=========================================="
echo "Oracle Benchmark Integration - Syntax Test"
echo "=========================================="
echo ""

# Check if Perl is available
if ! command -v perl &> /dev/null; then
    echo "ERROR: Perl not found in PATH"
    exit 1
fi

echo "✓ Perl found: $(perl -v | grep 'This is perl' | head -1)"
echo ""

# Check Perl syntax
echo "Checking Perl syntax..."
if perl -c scripts/getCamstarWafer2AssemblyGenealogy.pl 2>&1 | grep -q "syntax OK"; then
    echo "✓ Perl syntax check PASSED"
else
    echo "✗ Perl syntax check FAILED"
    perl -c scripts/getCamstarWafer2AssemblyGenealogy.pl
    exit 1
fi
echo ""

# Check for required modules
echo "Checking required Perl modules..."
MODULES=(
    "DBI"
    "DBD::Oracle"
    "JSON::PP"
    "DateTime"
    "DateTime::Format::Strptime"
    "File::Copy"
    "File::Basename"
    "File::Spec"
    "Getopt::Long"
    "Pod::Usage"
    "IO::Compress::Gzip"
    "Time::HiRes"
    "Fcntl"
)

MISSING_MODULES=()
for module in "${MODULES[@]}"; do
    if perl -M"$module" -e 1 2>/dev/null; then
        echo "  ✓ $module"
    else
        echo "  ✗ $module (MISSING)"
        MISSING_MODULES+=("$module")
    fi
done
echo ""

if [ ${#MISSING_MODULES[@]} -gt 0 ]; then
    echo "WARNING: Missing modules detected:"
    for module in "${MISSING_MODULES[@]}"; do
        echo "  - $module"
    done
    echo ""
    echo "Install missing modules with:"
    echo "  cpan ${MISSING_MODULES[@]}"
    echo ""
fi

# Check for database schema files
echo "Checking database schema files..."
if [ -f "pipeline-service-prod/sql/create_pipeline_runs.sql" ]; then
    echo "  ✓ create_pipeline_runs.sql found"
else
    echo "  ✗ create_pipeline_runs.sql NOT FOUND"
fi

if [ -f "pipeline-service-prod/sql/migration_add_metadata_benchmark.sql" ]; then
    echo "  ✓ migration_add_metadata_benchmark.sql found"
else
    echo "  ✗ migration_add_metadata_benchmark.sql NOT FOUND"
fi
echo ""

# Check for documentation files
echo "Checking documentation files..."
if [ -f "docs/oracle_benchmark_integration.md" ]; then
    echo "  ✓ oracle_benchmark_integration.md found"
else
    echo "  ✗ oracle_benchmark_integration.md NOT FOUND"
fi

if [ -f "scripts/ORACLE_BENCHMARK_QUICKSTART.txt" ]; then
    echo "  ✓ ORACLE_BENCHMARK_QUICKSTART.txt found"
else
    echo "  ✗ ORACLE_BENCHMARK_QUICKSTART.txt NOT FOUND"
fi

if [ -f "scripts/getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh" ]; then
    echo "  ✓ getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh found"
else
    echo "  ✗ getCamstarWafer2AssemblyGenealogy_oracle_benchmark_example.sh NOT FOUND"
fi
echo ""

# Display usage help
echo "Displaying script usage..."
perl scripts/getCamstarWafer2AssemblyGenealogy.pl --help 2>&1 | head -20
echo ""

echo "=========================================="
echo "Syntax validation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Set up Oracle database (see pipeline-service-prod/sql/)"
echo "2. Configure credentials (environment variables recommended)"
echo "3. Test with a pilot pipeline"
echo "4. Review docs/oracle_benchmark_integration.md for details"
