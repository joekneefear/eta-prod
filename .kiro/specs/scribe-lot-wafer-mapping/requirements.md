# Requirements Document: Scribe-to-Lot/Wafer Mapping Service

## Introduction

This service extracts and normalizes scribe, lot, and wafer number information from manufacturing workstream data (parameter history files). It creates bidirectional mapping data that enables traceability from individual scribe positions through production lots to wafer numbers, and vice versa. This supports defect analysis, yield tracking, and process correlation across manufacturing stages.

---

## Glossary

- **Scribe**: An individual test site or die position on a wafer. Identified by position codes like "A6", "E5", or directional notations like "LEFT", "CENTER", "RIGHT"
- **Wafer**: A silicon wafer containing multiple scribes/dies. Identified by wafer batch numbers like "GOXTWS1125"
- **Lot**: A manufacturing lot identifier (e.g., "KG4BNTCX"). May contain one or more wafers
- **Equipment Position**: Hardware identifier combining facility, probe, and position info (e.g., "THK-1-51T")
- **Parameter Set ID**: Test program identifier (e.g., "GMBG3002", "GTGX9A510_501")
- **Unit ID**: The scribe/wafer position within a test (e.g., "LEFT", "1", "A6")
- **Source Data**: Tab or whitespace-delimited workstream extract files (phist format)
- **Mapping Record**: A normalized record linking scribe ↔ wafer ↔ lot with test context
- **Bidirectional Mapping**: Scribe→Lot and Lot→Scribe lookup capability

---

## Requirements

### Requirement 1: Parse Workstream Extract Files

**User Story:** As a manufacturing engineer, I want to parse workstream parameter history files, so that I can extract lot and wafer information for scribe correlation analysis.

#### Acceptance Criteria

1. WHEN a workstream extract file (phist format) is provided, THE Parser SHALL read and validate the file format
2. WHEN the file contains parameter history records, THE Parser SHALL identify and extract each record's component fields
3. IF a record is malformed or missing required fields, THEN THE Parser SHALL log the error and skip the record
4. WHEN field extraction is complete, THE Parser SHALL normalize special characters and whitespace
5. WHEN parsing completes successfully, THE Parser SHALL return a collection of extracted records with all fields populated or marked as null

**Requirements:** 1.1, 1.2, 1.3, 1.4, 1.5

---

### Requirement 2: Extract Scribe Position Information

**User Story:** As a process engineer, I want to extract individual scribe positions from equipment identifiers and test parameters, so that I can map test results to specific scribe locations.

#### Acceptance Criteria

1. WHEN an equipment code (e.g., "THK-1-51T") is provided, THE Parser SHALL decompose it into facility, probe, position, and type components
2. WHEN a unit_id field (e.g., "LEFT", "CENTER", "A6", "1") is provided, THE Parser SHALL normalize it as a scribe position identifier
3. WHEN both equipment code and unit_id are available, THE Parser SHALL correlate them to identify the unique scribe position
4. IF either equipment code or unit_id is missing, THE Parser SHALL attempt to infer scribe position from available context or mark as "UNKNOWN"
5. WHEN multiple test measurements are present (c_value_1-5, d_value_1-5), THE Parser SHALL associate each measurement with a sequential site number (1, 2, 3...)

**Requirements:** 2.1, 2.2, 2.3, 2.4, 2.5

---

### Requirement 3: Extract Wafer/Lot Information

**User Story:** As a quality analyst, I want to extract and normalize wafer and lot identifiers from workstream records, so that I can establish production traceability.

#### Acceptance Criteria

1. WHEN a lot identifier (e.g., "KG4BNTCX") is present in a record, THE Extractor SHALL extract and store it as the primary lot reference
2. WHEN a wafer batch identifier (e.g., "GOXTWS1125") is present, THE Extractor SHALL extract and store it as the wafer reference
3. WHEN wafer identifier follows a structured pattern (e.g., "GOXTWS[batch]"), THE Extractor SHALL parse the pattern to identify wafer family and batch number
4. IF a record contains lot but no explicit wafer identifier, THEN THE Extractor SHALL generate a virtual wafer identifier using lot + equipment + timestamp
5. WHEN lot and wafer information is extracted, THE Extractor SHALL validate format and store with metadata timestamp

**Requirements:** 3.1, 3.2, 3.3, 3.4, 3.5

---

### Requirement 4: Create Bidirectional Mapping Records

**User Story:** As a data analyst, I want to create bidirectional mapping records linking scribes to lots and wafers, so that I can perform either forward (lot→scribe) or reverse (scribe→lot) lookups.

#### Acceptance Criteria

1. WHEN scribe, lot, and wafer information is extracted, THE Mapper SHALL create a mapping record containing all three identifiers
2. WHEN a mapping record is created, THE Mapper SHALL include contextual metadata: test_program, equipment_id, facility, timestamp, test_values
3. WHEN creating a bidirectional mapping, THE Mapper SHALL generate two lookup keys: (scribe→lot) and (lot→scribe)
4. IF the same scribe is tested multiple times (same lot, different tests), THE Mapper SHALL maintain separate records with unique test context
5. WHEN mapping is complete, THE Mapper SHALL assign a unique mapping_id for traceability and auditing

**Requirements:** 4.1, 4.2, 4.3, 4.4, 4.5

---

### Requirement 5: Generate Normalized Output

**User Story:** As a data engineer, I want to generate normalized output in multiple formats, so that downstream systems can consume mapping data in their preferred format.

#### Acceptance Criteria

1. WHEN mapping records are complete, THE Generator SHALL output data in CSV format with headers: scribe_id, lot_id, wafer_id, test_program, equipment_id, facility, sequence_number, site, test_values, timestamp, mapping_id
2. WHEN CSV output is generated, THE Generator SHALL escape special characters and handle embedded newlines correctly
3. WHERE CSV format is not suitable, THE Generator SHALL generate JSON output with hierarchical structure for complex relationships
4. WHEN output format is IFF (Internal File Format), THE Generator SHALL format data according to workstream standards with proper headers
5. WHEN multiple output formats are generated, THE Generator SHALL write all formats to separate files in the output directory

**Requirements:** 5.1, 5.2, 5.3, 5.4, 5.5

---

### Requirement 6: Validate Mapping Completeness

**User Story:** As a quality auditor, I want to validate that mapping data is complete and consistent, so that I can ensure data integrity for downstream analysis.

#### Acceptance Criteria

1. WHEN mapping records are generated, THE Validator SHALL check that each record contains scribe_id, lot_id, and wafer_id
2. IF a record is missing any required identifier, THE Validator SHALL mark it as incomplete and move it to error output
3. WHEN validating, THE Validator SHALL cross-reference lot_id and wafer_id for consistency (lot can have multiple wafers, but wafer belongs to single lot)
4. IF a scribe_id appears in multiple lots, THE Validator SHALL flag this as a potential data quality issue but allow it (different test runs)
5. WHEN validation completes, THE Validator SHALL generate a validation report with counts: total_records, valid_records, incomplete_records, inconsistent_records

**Requirements:** 6.1, 6.2, 6.3, 6.4, 6.5

---

### Requirement 7: Handle Multi-Site Test Data

**User Story:** As a process engineer, I want the system to handle multi-site test data where a single test record contains measurements for multiple scribe positions, so that I can correctly map each site to its scribe identifier.

#### Acceptance Criteria

1. WHEN a record contains multiple test values (c_value_1-5, d_value_1-5), THE Mapper SHALL treat each value as a separate measurement from a distinct scribe site
2. WHEN multiple values are present, THE Mapper SHALL create separate mapping records for each site with sequential site numbers (1, 2, 3, 4, 5)
3. IF a unit_id pattern is detected (e.g., "LEFT", "CENTER", "RIGHT"), THE Mapper SHALL use these as human-readable site identifiers instead of numeric site numbers
4. WHEN multiple sites are detected from a single record, THE Mapper SHALL preserve the relationship by assigning the same mapping_parent_id to all derived records
5. WHEN output is generated, THE Generator SHALL include site_number and unit_id in the output to distinguish multi-site results

**Requirements:** 7.1, 7.2, 7.3, 7.4, 7.5

---

### Requirement 8: Support Reverse Lookup (Scribe→Lot)

**User Story:** As a defect analyst, I want to perform reverse lookups from scribe ID to lot number, so that I can trace defects back to their source production lot.

#### Acceptance Criteria

1. WHEN a scribe_id is provided, THE LookupService SHALL return all lot_ids and wafer_ids associated with that scribe from the mapping data
2. WHEN multiple test programs have used the same scribe, THE LookupService SHALL return results grouped by test_program for clarity
3. IF a scribe has no corresponding lot mapping, THE LookupService SHALL return an empty result set and log the query for audit
4. WHEN returning results, THE LookupService SHALL include timestamp and test context to show when mapping was created
5. WHEN results are returned, THE LookupService SHALL allow filtering by date range, facility, or test program

**Requirements:** 8.1, 8.2, 8.3, 8.4, 8.5

---

### Requirement 9: Error Handling and Reporting

**User Story:** As a system administrator, I want comprehensive error handling and reporting, so that I can diagnose and resolve data quality issues.

#### Acceptance Criteria

1. WHEN a parsing error occurs, THE ErrorHandler SHALL log the error with record number, file name, and error description
2. WHEN extraction fails for a field, THE ErrorHandler SHALL record the failure and continue processing remaining records
3. IF validation fails, THE ErrorHandler SHALL write failed records to separate error output files (.err suffix)
4. WHEN processing completes, THE ErrorHandler SHALL generate an error report with: error_count, error_types, sample_errors
5. WHEN a critical error occurs (file not found, unreadable format), THE ErrorHandler SHALL halt processing and return appropriate error code

**Requirements:** 9.1, 9.2, 9.3, 9.4, 9.5

---

### Requirement 10: Command-Line Interface

**User Story:** As a data engineer, I want to invoke the mapping service via command line with clear options, so that I can automate lot-scribe mapping in production pipelines.

#### Acceptance Criteria

1. THE Service SHALL accept the following required arguments: -input <filepath>, -output <directory>
2. THE Service SHALL accept optional arguments: -format (csv|json|iff), -facility <name>, -product <pattern>, -logfile <path>
3. WHEN invoked with -help, THE Service SHALL display usage information and exit
4. WHEN invoked with -version, THE Service SHALL display version information and exit
5. WHEN all required arguments are provided, THE Service SHALL execute and return exit code 0 on success, non-zero on failure

**Requirements:** 10.1, 10.2, 10.3, 10.4, 10.5

---

## Usage Examples

### Basic Mapping Generation
```bash
perl scribe_lot_mapper.pl \
  -input workstream_data.phist \
  -output /data/mappings \
  -format csv
```

### With Filtering
```bash
perl scribe_lot_mapper.pl \
  -input workstream_data.phist \
  -output /data/mappings \
  -format csv,json \
  -facility BUCHEON \
  -product "GMBG*"
```

### Reverse Lookup Query
```bash
perl scribe_lot_mapper.pl \
  -lookup \
  -scribe A6 \
  -mapping-db /data/mappings/scribe_lot_map.csv
```

---

## Acceptance Testing Strategy

- Unit tests for each parser component (equipment parsing, field extraction, normalization)
- Integration tests for end-to-end file processing
- Validation tests for mapping consistency and completeness
- Error handling tests for malformed records and edge cases
- Performance tests with large files (1M+ records)

---

**Document Version:** 1.0  
**Created:** July 14, 2026  
**Status:** Requirements Gathering Phase
