"""Command-line interface for Scribe-Lot-Mapper service.

This module provides the CLI entry point using Click framework, orchestrating
all service components in the processing pipeline.
"""

from pathlib import Path
from typing import List, Optional

import click

from scribe_lot_mapper import __version__
from scribe_lot_mapper.config import ServiceConfig


@click.group()
@click.version_option(version=__version__)
def cli() -> None:
    """Scribe-to-Lot/Wafer Mapping Service.

    Manufacturing traceability service that extracts and normalizes scribe
    position, lot, and wafer identifiers from workstream parameter history files.
    Creates bidirectional mappings enabling both forward (lot→scribe) and reverse
    (scribe→lot) lookup for defect analysis and yield correlation.
    """
    pass


@cli.command()
@click.option(
    "--input",
    "-i",
    type=click.Path(exists=True),
    required=True,
    help="Input workstream extract file (phist format)",
)
@click.option(
    "--output",
    "-o",
    type=click.Path(),
    required=True,
    help="Output directory for mapping files",
)
@click.option(
    "--format",
    "-f",
    type=click.Choice(["csv", "json", "iff"], case_sensitive=False),
    multiple=True,
    default=["csv"],
    help="Output format(s) (default: csv)",
)
@click.option(
    "--facility",
    type=str,
    help="Filter by facility code (e.g., BUCHEON)",
)
@click.option(
    "--product",
    type=str,
    help="Filter by product pattern (e.g., GMBG*)",
)
@click.option(
    "--log-file",
    type=click.Path(),
    help="Log file path",
)
@click.option(
    "--log-level",
    type=click.Choice(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]),
    default="INFO",
    help="Logging level (default: INFO)",
)
@click.option(
    "--max-records",
    type=int,
    default=0,
    help="Maximum records to process (0 = unlimited)",
)
@click.option(
    "--dry-run",
    is_flag=True,
    help="Perform dry-run without writing output files",
)
@click.option(
    "--stop-on-error",
    is_flag=True,
    help="Halt on first error instead of continuing",
)
def map_records(
    input: str,
    output: str,
    format: tuple,
    facility: Optional[str],
    product: Optional[str],
    log_file: Optional[str],
    log_level: str,
    max_records: int,
    dry_run: bool,
    stop_on_error: bool,
) -> None:
    """Generate scribe-to-lot/wafer mappings from workstream data.

    Reads workstream parameter history files, extracts scribe and lot/wafer
    information, creates bidirectional mappings, and generates output in
    requested formats.

    Examples:

        # Basic usage
        scribe-lot-mapper map-records --input data.phist --output ./mappings

        # With filtering and multiple formats
        scribe-lot-mapper map-records \\
          --input data.phist \\
          --output ./mappings \\
          --format csv --format json \\
          --facility BUCHEON \\
          --product "GMBG*"

        # With logging and limits
        scribe-lot-mapper map-records \\
          --input data.phist \\
          --output ./mappings \\
          --log-file mapper.log \\
          --log-level DEBUG \\
          --max-records 100000
    """
    from logging.handlers import RotatingFileHandler
    import logging
    from fnmatch import fnmatch

    from scribe_lot_mapper.readers.file_reader import FileReader
    from scribe_lot_mapper.extractors.parser import Parser
    from scribe_lot_mapper.extractors.equipment_parser import EquipmentParser
    from scribe_lot_mapper.extractors.scribe_extractor import ScribeExtractor
    from scribe_lot_mapper.extractors.lot_wafer_extractor import LotWaferExtractor
    from scribe_lot_mapper.extractors.multi_site_detector import MultiSiteDetector
    from scribe_lot_mapper.mappers.mapping_generator import MappingGenerator
    from scribe_lot_mapper.validators.validator import Validator
    from scribe_lot_mapper.generators.csv_generator import CSVGenerator
    from scribe_lot_mapper.generators.json_generator import JSONGenerator
    from scribe_lot_mapper.generators.iff_generator import IFFGenerator
    from scribe_lot_mapper.services.lookup_service import LookupService
    from scribe_lot_mapper.services.error_handler import ErrorHandler
    from scribe_lot_mapper.exceptions import (
        ScribeLotMapperError,
        FileOperationError,
        ParsingError,
    )

    # =========================================================================
    # Setup Phase
    # =========================================================================

    # Configure logging
    logger = logging.getLogger("scribe_lot_mapper")
    logger.setLevel(log_level)
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(log_level)
    console_formatter = logging.Formatter("%(levelname)s: %(message)s")
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)

    # File handler (if specified)
    if log_file:
        try:
            file_handler = RotatingFileHandler(
                log_file,
                maxBytes=10 * 1024 * 1024,  # 10 MB
                backupCount=5,
            )
            file_handler.setLevel(log_level)
            file_formatter = logging.Formatter(
                "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
            )
            file_handler.setFormatter(file_formatter)
            logger.addHandler(file_handler)
            click.echo(f"Logging to: {log_file}", err=False)
        except Exception as e:
            logger.warning(f"Could not open log file {log_file}: {e}")

    logger.info("Starting Scribe-Lot-Mapper")
    logger.info(f"Input: {input}")
    logger.info(f"Output: {output}")
    logger.info(f"Formats: {', '.join(format)}")
    if max_records > 0:
        logger.info(f"Max records: {max_records}")
    if dry_run:
        logger.warning("DRY-RUN mode: No files will be written")

    try:
        # =====================================================================
        # Input Validation Phase
        # =====================================================================

        input_path = Path(input)
        output_path = Path(output)

        # Validate input file exists
        if not input_path.exists():
            raise FileOperationError(f"Input file not found: {input}")

        # Create output directory if needed
        output_path.mkdir(parents=True, exist_ok=True)
        logger.info(f"Output directory: {output_path}")

        # =====================================================================
        # Component Initialization Phase
        # =====================================================================

        # Initialize all components
        file_reader = FileReader(str(input_path))
        parser = Parser()
        equipment_parser = EquipmentParser()
        scribe_extractor = ScribeExtractor()
        lot_wafer_extractor = LotWaferExtractor()
        multi_site_detector = MultiSiteDetector()
        mapping_generator = MappingGenerator(id_strategy="uuid")
        validator = Validator()
        error_handler = ErrorHandler()

        # Initialize output generators
        generators = {}
        for fmt in format:
            fmt_lower = fmt.lower()
            if fmt_lower == "csv":
                generators["csv"] = CSVGenerator(str(output_path))
            elif fmt_lower == "json":
                generators["json"] = JSONGenerator(str(output_path))
            elif fmt_lower == "iff":
                generators["iff"] = IFFGenerator(str(output_path))

        logger.info(f"Initialized {len(generators)} output generator(s)")

        # =====================================================================
        # Processing Pipeline Phase
        # =====================================================================

        # Statistics tracking
        stats = {
            "total_records_read": 0,
            "records_parsed": 0,
            "records_expanded": 0,
            "mappings_generated": 0,
            "records_validated": 0,
            "valid_records": 0,
            "invalid_records": 0,
        }

        all_mappings = []

        # Validate input file format before processing
        logger.info("Validating input file format...")
        try:
            file_reader.validate()
            logger.info("Input file format validated")
            # Get detected delimiter
            detected_delimiter = file_reader.get_delimiter()
            logger.info(f"Detected delimiter: {repr(detected_delimiter)}")
        except FileOperationError as e:
            logger.error(f"File validation failed: {e}")
            raise

        # Process records
        logger.info("Starting record processing pipeline...")

        with file_reader:
            for line_number, raw_line in enumerate(file_reader, start=1):
                # Check max records limit
                if max_records > 0 and line_number > max_records:
                    logger.info(f"Reached max records limit: {max_records}")
                    break

                # Skip empty lines
                if not raw_line.strip():
                    continue

                stats["total_records_read"] += 1

                try:
                    # Step 1: Parse raw record with detected delimiter
                    parsed_record = parser.parse_record(raw_line, delimiter=detected_delimiter)
                    stats["records_parsed"] += 1

                    # Step 2: Equipment parsing
                    equipment_info = equipment_parser.parse(parsed_record.type_id)

                    # Step 3: Extract scribe, lot, wafer
                    scribe_id = scribe_extractor.extract(
                        parsed_record.unit_id,
                        equipment_info,
                        site_number=1,
                    )
                    lot_id, wafer_id, wafer_family = lot_wafer_extractor.extract(
                        parsed_record
                    )

                    # Step 4: Apply facility/product filters if specified
                    if facility and facility not in parsed_record.facility:
                        continue
                    if product and not fnmatch(parsed_record.parameter_set_id, product):
                        continue

                    # Step 5: Detect and expand multi-site records
                    site_count = multi_site_detector.detect(parsed_record)
                    if site_count > 1:
                        # Expand multi-site record
                        expanded_records = multi_site_detector.expand(parsed_record)
                        stats["records_expanded"] += len(expanded_records) - 1

                        # Generate mapping for each expanded record
                        parent_mapping_id = None  # Will be set to first mapping ID
                        for site_index, expanded_record in enumerate(expanded_records, start=1):
                            # Re-extract for this specific site
                            site_scribe = scribe_extractor.extract(
                                expanded_record.unit_id,
                                equipment_info,
                                site_number=site_index,
                            )

                            # Generate mapping
                            mapping = mapping_generator.generate(
                                scribe_id=site_scribe,
                                lot_id=lot_id,
                                wafer_id=wafer_id,
                                parsed_record=expanded_record,
                                site_number=site_index,
                                parent_mapping_id=parent_mapping_id,
                                test_value=expanded_record.c_values[site_index - 1]
                                if site_index <= len(expanded_record.c_values)
                                else "",
                                wafer_family=wafer_family,
                            )

                            # Track parent for subsequent sites
                            if parent_mapping_id is None:
                                parent_mapping_id = mapping.mapping_id

                            all_mappings.append(mapping)
                            stats["mappings_generated"] += 1
                    else:
                        # Single-site record
                        mapping = mapping_generator.generate(
                            scribe_id=scribe_id,
                            lot_id=lot_id,
                            wafer_id=wafer_id,
                            parsed_record=parsed_record,
                            site_number=1,
                            test_value=parsed_record.c_values[0]
                            if parsed_record.c_values
                            else "",
                            wafer_family=wafer_family,
                        )

                        all_mappings.append(mapping)
                        stats["mappings_generated"] += 1

                except (ParsingError, Exception) as e:
                    error_handler.log_error(
                        error_type=type(e).__name__,
                        message=str(e),
                        context={
                            "line_number": line_number,
                            "raw_line": raw_line[:100],  # First 100 chars
                        },
                    )

                    if stop_on_error:
                        logger.error(f"Stopping on error at line {line_number}: {e}")
                        raise
                    continue

                # Progress reporting
                if stats["records_parsed"] % 10000 == 0:
                    logger.info(
                        f"Processed {stats['records_parsed']} records, "
                        f"generated {stats['mappings_generated']} mappings"
                    )

        logger.info(f"Completed record processing: {stats['records_parsed']} records parsed")

        # =====================================================================
        # Validation Phase
        # =====================================================================

        logger.info("Starting validation phase...")
        valid_records, invalid_records = validator.validate_batch(all_mappings)
        stats["records_validated"] = len(all_mappings)
        stats["valid_records"] = len(valid_records)
        stats["invalid_records"] = len(invalid_records)

        validation_report = validator.get_report()
        logger.info(validator.get_validation_summary())

        # =====================================================================
        # Output Generation Phase
        # =====================================================================

        if not dry_run:
            logger.info("Generating output files...")

            # Generate output in requested formats
            for fmt, generator in generators.items():
                try:
                    logger.info(f"Generating {fmt.upper()} output...")
                    generator.generate(valid_records)
                    logger.info(f"Generated {fmt.upper()} output successfully")
                except Exception as e:
                    logger.error(f"Failed to generate {fmt} output: {e}")
                    error_handler.log_error(
                        error_type="OutputError",
                        message=str(e),
                        context={"format": fmt},
                    )

            # Write invalid records to error file if any
            if invalid_records:
                logger.info(f"Writing {len(invalid_records)} invalid records to error file...")
                error_file = output_path / "mappings.err"
                try:
                    # Use CSV generator for error output
                    csv_gen = CSVGenerator(str(output_path))
                    csv_gen.generate(invalid_records, filename="mappings.err")
                    logger.info(f"Error records written to: {error_file}")
                except Exception as e:
                    logger.error(f"Failed to write error file: {e}")
        else:
            logger.warning("DRY-RUN: Skipping output file generation")

        # =====================================================================
        # Reporting Phase
        # =====================================================================

        logger.info("\n" + "=" * 70)
        logger.info("FINAL PROCESSING REPORT")
        logger.info("=" * 70)
        logger.info(f"Total records read:    {stats['total_records_read']}")
        logger.info(f"Records parsed:        {stats['records_parsed']}")
        logger.info(f"Records expanded:      {stats['records_expanded']}")
        logger.info(f"Mappings generated:    {stats['mappings_generated']}")
        logger.info(f"Valid records:         {stats['valid_records']}")
        logger.info(f"Invalid records:       {stats['invalid_records']}")
        logger.info(f"Valid percentage:      {validation_report['valid_percentage']:.2f}%")

        if error_handler.error_summary:
            logger.info("\nError Summary:")
            for error_type, count in error_handler.error_summary.items():
                logger.info(f"  {error_type}: {count}")

        logger.info("=" * 70)
        logger.info("Processing completed successfully")

        # Exit with success code
        exit(0)

    except ScribeLotMapperError as e:
        logger.error(f"Service error: {e}")
        click.echo(f"Error: {e}", err=True)
        exit(1)

    except KeyboardInterrupt:
        logger.warning("Processing interrupted by user")
        click.echo("\nProcessing interrupted", err=True)
        exit(130)

    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        click.echo(f"Unexpected error: {e}", err=True)
        exit(1)


@cli.command()
@click.option(
    "--scribe",
    type=str,
    required=True,
    help="Scribe ID to search for",
)
@click.option(
    "--mapping-db",
    type=click.Path(exists=True),
    required=True,
    help="Path to mapping database (CSV file)",
)
@click.option(
    "--start-date",
    type=str,
    help="Filter by start date (ISO 8601 format)",
)
@click.option(
    "--end-date",
    type=str,
    help="Filter by end date (ISO 8601 format)",
)
@click.option(
    "--facility",
    type=str,
    help="Filter by facility code",
)
@click.option(
    "--format",
    "-f",
    type=click.Choice(["text", "csv", "json"], case_sensitive=False),
    default="text",
    help="Output format (default: text)",
)
def lookup(
    scribe: str,
    mapping_db: str,
    start_date: Optional[str],
    end_date: Optional[str],
    facility: Optional[str],
    format: str,
) -> None:
    """Lookup lots and wafers associated with a scribe.

    Performs reverse lookup in mapping database to find all lots and wafers
    that have been tested on the specified scribe.

    Examples:

        # Basic lookup
        scribe-lot-mapper lookup \\
          --scribe "THK_1_51_LEFT_1" \\
          --mapping-db ./mappings/mappings.csv

        # With date and facility filtering
        scribe-lot-mapper lookup \\
          --scribe "THK_1_51_LEFT_1" \\
          --mapping-db ./mappings/mappings.csv \\
          --start-date "2026-07-01" \\
          --end-date "2026-07-14" \\
          --facility "BUCHEON"
    """
    import csv
    import json
    import logging
    from scribe_lot_mapper.models import MappingRecord
    from scribe_lot_mapper.services.lookup_service import LookupService

    logger = logging.getLogger("scribe_lot_mapper")
    logger.setLevel("INFO")

    # Setup console logging if not already configured
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        logger.addHandler(handler)

    try:
        # =====================================================================
        # Load Mapping Database Phase
        # =====================================================================

        logger.info(f"Loading mapping database: {mapping_db}")
        mapping_db_path = Path(mapping_db)

        if not mapping_db_path.exists():
            click.echo(f"Error: Mapping database not found: {mapping_db}", err=True)
            exit(1)

        # Load CSV file into MappingRecord objects
        mappings = []
        with open(mapping_db_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row_num, row in enumerate(reader, start=2):  # Start at 2 (header is 1)
                try:
                    mapping = MappingRecord(
                        mapping_id=row.get("mapping_id", ""),
                        scribe_id=row.get("scribe_id", ""),
                        lot_id=row.get("lot_id", ""),
                        wafer_id=row.get("wafer_id", ""),
                        test_program=row.get("test_program", ""),
                        equipment_id=row.get("equipment_id", ""),
                        facility=row.get("facility", ""),
                        timestamp=row.get("timestamp", ""),
                        created_at=row.get("created_at", ""),
                        wafer_family=row.get("wafer_family", ""),
                        wafer_batch=int(row.get("wafer_batch", 0)) if row.get("wafer_batch") else 0,
                        test_value=row.get("test_value", ""),
                        sequence_number=int(row.get("sequence_number", 0))
                        if row.get("sequence_number")
                        else 0,
                        site_number=int(row.get("site_number", 1))
                        if row.get("site_number")
                        else 1,
                        unit_id=row.get("unit_id", ""),
                        validation_status=row.get("validation_status", "valid"),
                    )
                    mappings.append(mapping)
                except Exception as e:
                    logger.warning(f"Skipping malformed row {row_num}: {e}")
                    continue

        logger.info(f"Loaded {len(mappings)} mapping records")

        if not mappings:
            click.echo("Error: No valid mapping records found in database", err=True)
            exit(1)

        # =====================================================================
        # Initialize Lookup Service and Build Indices
        # =====================================================================

        lookup_service = LookupService()
        lookup_service.load_mappings(mappings)
        logger.info("Lookup indices built")

        # =====================================================================
        # Perform Lookup Query
        # =====================================================================

        click.echo("\n" + "=" * 70)
        click.echo(f"Scribe Lookup: {scribe}")
        click.echo("=" * 70)

        # Execute lookup query
        if facility:
            # Filter by facility first
            facility_records = lookup_service.query_by_facility(facility)
            results = lookup_service.find_lots_by_scribe(scribe)
            results = [
                (lot, wafer, ctx)
                for lot, wafer, ctx in results
                if ctx.get("facility") == facility
            ]
        else:
            results = lookup_service.find_lots_by_scribe(scribe)

        # Apply date filtering if specified
        if start_date or end_date:
            filtered_results = []
            for lot, wafer, ctx in results:
                timestamp = ctx.get("timestamp", "")
                if start_date and timestamp < start_date:
                    continue
                if end_date and timestamp > end_date:
                    continue
                filtered_results.append((lot, wafer, ctx))
            results = filtered_results

        # =====================================================================
        # Output Results
        # =====================================================================

        if not results:
            click.echo(f"\nNo results found for scribe: {scribe}")
            if facility:
                click.echo(f"Facility filter: {facility}")
            if start_date:
                click.echo(f"Start date: {start_date}")
            if end_date:
                click.echo(f"End date: {end_date}")
            exit(0)

        click.echo(f"\nFound {len(results)} lot/wafer combination(s):\n")

        if format.lower() == "text":
            # Text format output
            for lot, wafer, ctx in results:
                click.echo(f"  Lot: {lot}")
                click.echo(f"    Wafer: {wafer}")
                click.echo(f"    Test Program: {ctx.get('test_program')}")
                click.echo(f"    Facility: {ctx.get('facility')}")
                click.echo(f"    Timestamp: {ctx.get('timestamp')}")
                click.echo(f"    Site: {ctx.get('site_number')}")
                if ctx.get("unit_id"):
                    click.echo(f"    Unit ID: {ctx.get('unit_id')}")
                click.echo()

        elif format.lower() == "csv":
            # CSV format output
            writer = csv.writer(click.get_text_stream("stdout"))
            writer.writerow(
                ["lot_id", "wafer_id", "test_program", "facility", "timestamp", "site_number", "unit_id"]
            )
            for lot, wafer, ctx in results:
                writer.writerow(
                    [
                        lot,
                        wafer,
                        ctx.get("test_program"),
                        ctx.get("facility"),
                        ctx.get("timestamp"),
                        ctx.get("site_number"),
                        ctx.get("unit_id", ""),
                    ]
                )

        elif format.lower() == "json":
            # JSON format output
            output_data = {
                "scribe_id": scribe,
                "results": [
                    {
                        "lot_id": lot,
                        "wafer_id": wafer,
                        "test_program": ctx.get("test_program"),
                        "facility": ctx.get("facility"),
                        "timestamp": ctx.get("timestamp"),
                        "site_number": ctx.get("site_number"),
                        "unit_id": ctx.get("unit_id"),
                    }
                    for lot, wafer, ctx in results
                ],
            }
            click.echo(json.dumps(output_data, indent=2))

        click.echo("\n" + "=" * 70)
        click.echo(f"Query completed: {len(results)} result(s)")
        click.echo("=" * 70)

    except Exception as e:
        logger.exception(f"Lookup error: {e}")
        click.echo(f"Error: {e}", err=True)
        exit(1)


if __name__ == "__main__":
    cli()
