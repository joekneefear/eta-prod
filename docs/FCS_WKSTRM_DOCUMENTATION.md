# FCS_WKSTRM.PL - Comprehensive Documentation

## Overview

**Script Name:** `fcs_wkstrm.pl`  
**Purpose:** Data processing and transformation utility for manufacturing test data (workstream data)  
**Language:** Perl  
**Total Lines:** ~4,039  
**Version:** 1.0 (25-02-2015) with ongoing updates through 2023-07-03

This script processes ZIP-archived manufacturing data files and transforms them into standardized output formats. It enriches raw workstream data with metadata, validates information against reference databases, and generates multiple output file types for downstream analysis.

---

## Core Functionality

### Primary Purpose
Extract and process manufacturing facility data from compressed archives, enriching it with metadata and generating standardized output files in various formats (LEH, FS, LOSS, LOTEVENT, LATT, EHIST, and LEHS).

### Key Operations
1. **ZIP File Extraction** - Decompresses input archive and handles nested gzip files
2. **Data Parsing** - Reads and parses multiple data source files using format specifications
3. **Metadata Enrichment** - Lookup and populate product, lot, and facility information
4. **Data Validation** - Validates required fields and cross-references with databases
5. **File Generation** - Creates multiple output formats with appropriate headers and data
6. **Error Handling** - Separate output streams for valid and invalid records

---

## Command-Line Interface

### Usage
```bash
perl fcs_wkstrm.pl -out <output_dir> -fmtdir <format_dir> -loc <location> [options] <zipfile>
```

### Required Arguments
| Argument | Type | Description |
|----------|------|-------------|
| `-out` | string | Output directory for processed files (created if not exists) |
| `-fmtdir` | string | Directory containing format specification files (*.bcp_fmt) |
| `-loc` | string | Facility/location code (defines equipment and configuration) |
| `<zipfile>` | path | Input ZIP archive containing raw data files |

### Optional Arguments
| Argument | Type | Description |
|----------|------|-------------|
| `-product` | regex | Filter output by product ID pattern (LEH and FS only) |
| `-type` | string | Output file type filter: LEH, FS, LOSS, LOTEVENT, LATT, EHIST, LEHS (default: all) |
| `-finallot` | flag | Process as final lot test data |
| `-fab8` | flag | Use FAB8 equipment configuration |
| `-fab6` | flag | Use FAB6 equipment configuration |
| `-epi` | flag | Use EPI equipment configuration |
| `-waferproduct` | flag | Append "_WAFER" suffix to product IDs |
| `-lehgroup` | flag | Group LEH output files by program hierarchy |
| `-convert` | flag | Generate CSV-only output (skip IFF generation) |
| `-fork` | string | Fork output files to alternate directory |
| `-logfile` | path | Specify custom log file path |
| `-debug` | flag | Enable debug-level logging |
| `-trace` | flag | Enable trace-level logging |
| `-pplog` | flag | Enable PP (Production Planning) logging |
| `-help` | flag | Display usage information |
| `-version` | flag | Display version information |

---

## Global Data Structures

### Configuration Hashes

**%hOptions** - Command-line argument storage
- Stores all parsed command-line options
- Keys: out, FORK, fmtdir, product, convert, logfile, loc, type, LEHGROUP, FINALLOT, DEBUG, TRACE, FACILITYFILE, FAB8, FAB6, EPI, PPLOG, etc.

### Processing Hashes

| Hash Name | Purpose | Key Structure |
|-----------|---------|---|
| `%operinfo` | Operation metadata (step descriptions, groups) | `operation\|facility` |
| `%prodinfo` | Product information from references | `product_id` |
| `%prodfile` | Product data from input files | `product_id` |
| `%lotinfo` | Lot type mappings | `lot_id` |
| `%lhistinfo` | Lot history records (LEH output data) | `lot\|operation\|description\|type\|facility` |
| `%lhistlossinfo` | Loss data grouped by lot/transaction | `lot_id_timestamp` |
| `%lhistfsinfo` | FabSite data with equipment info | `lot\|facility\|parasetid\|parasetver\|datetime` |
| `%lhistloteventinfo` | Lot event records | `product_id` |
| `%lhistoffinfo` | Offline metrology records | Facility and key combinations |
| `%ehistinfo` | Entity history records | `entity_id` |
| `%ehistupdinfo` | Entity history updates | `entity_id` |
| `%ehistoffinfo` | Entity offline records | `parasetid\|parasetver\|datetime\|facility\|typeid` |
| `%phistinfo` | Parameter history data | `parasetid\|parasetver\|paraname\|datetime\|facility\|typeid\|seqnum\|unitid` |
| `%entinfo` | Entity type mappings | `entity_id\|facility` |
| `%parminfo` | Parameter group info | `parameter_name\|facility` |
| `%sicinfo` | Silicon Carbide lot tracking | `lot_id` → attributes hash |

### Output Hashes

| Hash Name | Purpose |
|-----------|---------|
| `%output` | Valid records ready for output |
| `%erroutput` | Invalid/missing data records (separate output) |
| `%headers` | Cached file headers to avoid regeneration |
| `%offoutput` | Offline metrology output data |
| `%lothashes` | Cache for lot metadata lookups |
| `%lehprogramhash` | LEH program naming for grouped output |
| `%missingLot` | Tracking of lots with lookup failures |
| `%missingProduct` | Tracking of products with lookup failures |

### Special Variables

```perl
%m2d              # Month name to digit mapping (JAN->01, etc.)
$NA               # Constant string "N/A" for null values
$sVersionId       # Script version ID from CVS
$perlname         # Perl executable name ("perl_db" for debug mode)
$readWksm         # Path to read_wksm.pl format parser script
$normalizeChars   # Hash of special character to ASCII mappings
```

---

## Main Processing Flow

### Execution Sequence

1. **Initialization** (`Initialize_argument()`)
   - Parse command-line arguments
   - Validate required directories
   - Load facility configuration file
   - Initialize logging and PPLogger
   - Extract input file directory path

2. **ZIP Processing** (`ProcessZipFile()`)
   - Extract archive to input directory
   - Handle nested gzip decompression
   - First pass: Parse metadata files (product, operation, entity, lot_attr)
   - Second pass: Parse transaction files (lot_v21, lhist, phist, ehist, parm)
   - Third pass: Generate output files (LEH, FS, LOSS, LOTEVENT, EHIST)
   - Cleanup extracted temporary files

3. **Output Generation**
   - Generate output based on `-type` filter
   - Apply product pattern filtering if specified
   - Separate valid from missing/invalid records
   - Compress output with gzip
   - Fork to alternate location if configured

4. **Exit** - Return success status

---

## Input File Types and Processing

### Metadata Files (First Pass)

**Product File** (product.*, prod.*)
- Columns: product_id, product_group, device_id, pkg_id
- Stored in: `%prodfile`
- Fallback data when lot metadata lookup fails

**Operation File** (oper.*, operation.*)
- Columns: operation, facility, short_description, oper_group_1/2/3, units
- Stored in: `%operinfo`
- Provides operation context for all data types

**Entity File** (_ent, _entity)
- Columns: entity_id, facility, entity_type, entity_description, entity_location
- Stored in: `%entinfo`
- Maps equipment IDs to entity types
- Output: `.ent` file with all entity mappings

**Lot Attribute File** (lot_attr)
- Columns: lot_id, attribute_number, attribute_name, attribute_type, attribute_value
- Special handling for "EPI SLOT" attributes (SiC tracking)
- Output: `.latt` files (max 100 lots per file)

### Transaction Files (Second Pass)

**Lot Version File** (lot_v21)
- Columns: lot_id, lot_type
- Stored in: `%lotinfo`

**Lot History File** (lhist, lot_history) - **Complex, Critical**
- Contains all lot event and loss data
- Parsed row-by-row with extensive validation
- Populates: `%lhistinfo`, `%lhistlossinfo`, `%lhistfsinfo`, `%lhistloteventinfo`
- Handles multi-step lot tracking with TrackIN/TrackOUT times

**Parameter History File** (phist, parameter_history)
- Columns: parameter_set_id, parameter_set_version, parameter_name, c_value_1-5, d_value_1-5, high/low limits, sequence_number, unit_id, number_of_values, format_flag, date_time, facility, type_id
- Stored in: `%phistinfo`
- Values formatted as comma-separated list (c_value for text, d_value for numeric)

**Parameter File** (_parm, _parameter)
- Columns: parameter_name, facility, parameter_group_1/2/3
- Stored in: `%parminfo`

**Entity History File** (_ehist, _entity_history)
- Entity status tracking with multiple status flags
- Stored in: `%ehistinfo`, `%ehistupdinfo`
- Output: `.ehist` CSV file

**Lot Detail History File** (_dllh)
- Augmented with lot and owner information
- Output: `.ltev` files

**Entity Attribute File** (_eatr, _entity_attribute)
- Output: `.eatr` CSV files

**LEHS File** (_lehs)
- Advanced lot event history with step information
- Special processing via `PDF::Parser::BK_LEHS` module

---

## Output File Types

### LEH (Lot Event History)
- **Format:** IFF (Internal File Format)
- **Content:** Chronological lot movement through operations
- **Columns:** lot, lot_type, sequence_number, condition1-3, unit, step, owner, PI, PO, loss_quantity, product, pkg_id, stage, lot_quantity, PE, rework flags, recipe, TI/TO times, entity_type, source_lot, lot_class
- **Grouping:** Can be grouped by program hierarchy with `-lehgroup`
- **Filtering:** Product pattern filter supported

### FS (FabSite)
- **Format:** IFF with vertical tab (Ctrl-K) separators
- **Content:** Parametric test data with equipment location mapping
- **Columns:** date_time, lot_id, fab, sequence_number, step_info, parameter_data, results, limits, entity_info, source_lot
- **Multi-lot:** Handles equipment with multiple concurrent lots

### LOSS
- **Format:** IFF
- **Content:** Scrap and rework loss tracking
- **Components:** Header, sub_lot designation, equipment ID, loss categories (loss_category_1-12 with quantities), good units, total loss, qty_in
- **Special:** Calculates aggregate loss values

### LOTEVENT (Lot Event)
- **Format:** IFF
- **Content:** Discrete lot state changes (hold, release, scrap, rework)
- **Event Types:** Hold Lot, Release Lot, Scrap, Rework
- **Columns:** lot_id, facility, transaction, transaction_date_time, operation, step, operator_id, entity_type, equipment_id, product_id, comment, event, eventtype, rework_cat, hold_flag/cat/name/note, unit_change, lot_quantity_new, loss_quantity, source_lot, lot_class

### LATT (Lot Attributes)
- **Format:** Tab-separated with appended source_lot and lot_class
- **Content:** Lot attribute key-value pairs
- **Limit:** 100 lots per output file (splits into .1, .2, etc.)
- **Special:** Strips single quotes from attribute values

### EHIST (Entity History)
- **Format:** CSV
- **Content:** Equipment/entity state history and availability
- **Columns:** entity_type, entity_id, transaction_date_time, facility, time_in_status, standard_status, old_standard_status, status_1-9, comment, operator_id, new_availability, oosi_flag, fail_flag, frdt_flag, dt_flag
- **Filter:** Excludes last transaction per entity (non-qualified records)

### OFF (Offline Metrology)
- **Format:** Pipe-delimited
- **Content:** Parametric measurements for offline analysis
- **Columns:** date_time, fab, entity_type, entity_id, unit_id, site, parameter_set_id, parameter_set_version, parameter_name, exceed_limit, test_flag, parameter_grp_1/2/3, format_flag, result, low_lim, high_lim

### LEHS (Lot Event History with Steps)
- **Format:** IFF
- **Content:** Advanced lot event tracking with process steps
- **Metadata:** Enriched with product, process, and source lot information

---

## Key Subroutines

### Main Control Flow

**Initialize_argument()**
- Parses command-line options with GetOptions
- Loads facility configuration from INI file
- Validates required directories (out, fmtdir)
- Sets up logging and PPLogger
- Extracts input directory from ZIP file path
- Returns: 1 on success

**ProcessZipFile()**
- Extracts ZIP archive using Archive::Extract
- Handles gzip files within archive
- Orchestrates three-pass file processing
- Calls appropriate Process*File() subroutines
- Cleans up temporary extracted files

### Metadata Parsing

**ProcessProductFile(basename, ext)**
- Parses product catalog
- Builds %prodfile with package, family, process info
- Handles -waferproduct suffix option

**ProcessOperFile(basename, ext)**
- Parses operation definitions
- Builds %operinfo with descriptions and operation groups
- Validates facility assignment

**ProcessAndOutputEntFile(basename, ext)**
- Parses entity (equipment) catalog
- Builds %entinfo mapping
- Generates `.ent` output file with all entities

**ProcessLotV21File(basename, ext)**
- Parses lot type information
- Builds simple %lotinfo lookup

### Transaction Processing

**ProcessLhistFile(basename, ext)** - **Complex**
- Parses lot history (largest, most complex file)
- Handles special character normalization
- Performs metadata lookup for each lot via GetMetaByLot()
- Populates four related hashes:
  - %lhistinfo (LEH data)
  - %lhistlossinfo (LOSS data)
  - %lhistfsinfo (FS data)
  - %lhistloteventinfo (LOT EVENT data)
- Cross-references with operation and entity info
- Detects event types (Hold, Release, Scrap, Rework)
- Tracks TrackIN and TrackOUT times

**ProcessPhistFile(basename, ext)**
- Parses parameter history
- Handles both text (c_value) and numeric (d_value) formats
- Builds %phistinfo with limit information
- Formats datetime values
- Validates sequence numbers and facility codes

**ProcessParmFile(basename, ext)**
- Parses parameter groups
- Builds %parminfo for FabSite grouping

**ProcessAndOutputEhistFile(basename, ext)**
- Parses entity history with multiple status fields
- Builds %ehistinfo with qualification tracking
- Calls ProcessAndOutputEhistUpdFile() for update records
- Generates `.ehist` output

### Output Generation

**OutputLEH()**
- Iterates %lhistinfo
- Applies product filter if specified
- Generates headers via PrintLEHHeader()
- Outputs valid/error versions

**OutputFabSite()**
- Complex multi-lot handling
- Processes directional units (LEFT, CENTER, RIGHT, TOP, BOTTOM)
- Calls OutputFabSiteLine() for each parameter value
- Tracks sequence numbering per site
- Applies product filter

**OutputLoss()**
- Processes %lhistlossinfo
- Generates loss data with:
  - Operation padding (zero-fill to 4 digits)
  - Loss category aggregation
  - Calculated _GOOD, _TOTAL_LOSS, _QTY_IN fields
  - Stage routing information
  - Operation group tags

**OutputLotEvent()**
- Processes %lhistloteventinfo
- Filters by event type
- Validates lot and product existence

**OutputEhist()**
- Formats entity history CSV
- Filters qualified records
- Tracks latest transaction per entity
- Handles update records separately

**OutputMetrologyOffline()**
- Processes offline measurement data
- Integrates parameter history with entity data

**processLehWithStep(basename, ext)** - Advanced
- Uses PDF::Parser::BK_LEHS for complex lot parsing
- Metadata enrichment via getBKLEHSmetadata()
- Dynamic file naming based on lot groups

### Output File Management

**OutputFiles(ext, ifdata, ifSubfolder)**
- Writes collected %output hash to IFF files
- Writes %erroutput to separate error files
- Creates subdirectories for grouped output (LEH)
- Optionally groups by program hierarchy
- Handles gzip compression or fork directory copy
- Uses PDF::DpWriter for IFF generation

**OutputMetrologyOfflineFiles(ext)**
- Writes pipe-delimited offline data
- Simpler format without IFF encoding

**OutputLatt(basename, ext, newext)**
- Parses lot attributes
- Limits output to 100 lots per file
- Splits across multiple output files if needed
- Tracks SiC lot attributes for special handling

### Utility Functions

**PrintLEHHeader(product, fab, fname)**
- Generates LEH header via PDF::DpData::HeaderShort
- Queries metadata database
- Falls back to %prodfile on failure
- Constructs program name from PROCESS/PACKAGE, facility, "WKS"
- Caches in %lehprogramhash

**PrintFSHeader(product, fab)**
- Generates FabSite header via PDF::DpData::HeaderLong
- Sets ERT URL, EQUIP6_ID
- Similar fallback strategy

**PrintLotEventHeader(product, fab)**
- Generates LOT EVENT header
- Simpler than FS/LEH headers

**GetMetaByLot(lot, in_product)**
- Core metadata lookup function
- Calls getRefdb->getMetaData() or getMetaDataFinalLot()
- Caches results in %lothashes
- Falls back to %prodfile on failure
- Returns: (source_lot, lot_owner, lot_class, product)

**FormatField(value)**
- Returns "N/A" for empty/whitespace values
- Returns original value otherwise
- Used for output field formatting

**FormatDate(datetime_string)**
- Parses date strings: "JAN 02 2004 14:30:25:000PM"
- Converts to: "2004-01-02 14:30:25"
- Handles 12-hour AM/PM conversion
- Handles midnight edge case (12:xx AM → 00:xx)

**ReplaceSpecialChars(string)**
- Normalizes Unicode characters to ASCII
- Uses %normalizeChars mapping
- Calls unidecode() from Text::Unidecode

**formatSourceLot(sourcelot, lot)**
- Returns source_lot if valid
- Appends ".S" suffix if needed for Maine SiC
- Defaults to "lot.S" if source_lot is N/A or empty

**getLotAttrColumns(line)**
- Parses comma-separated lot attribute line
- Extracts: lot_id, attribute_number, attribute_name, attribute_type, attribute_value
- Handles (A)SCII/(N)umeric type indicators
- Handles blank type indicator as space
- Strips single quotes from values
- Returns: (lot, attr_num, attr_name, attr_type, attr_val)

**MakeSubDir(subfolder)**
- Creates output subdirectory if missing
- Used for organized output grouping

**OutputFabSiteLine(holder, site_in, unitid)**
- Core FabSite output logic
- Processes parameter history for a specific lot/equipment combination
- Iterates through parameter values
- Increments site numbering
- Handles special SiC slot tracking
- Complex multi-lot handling for equipment

### Data Validation

**AddLotInfoForCSVFile(basename, ext, newext)**
- Enhances CSV output with lot metadata
- Calls GetMetaByLot() for enrichment
- Appends SOURCE_LOT and LOT_OWNER columns

---

## Dependencies and Modules

### Perl Built-in Modules
- **strict** - Strict variable declaration requirements
- **FindBin** - Script directory location
- **Getopt::Long** - Command-line argument parsing (case-insensitive)
- **File::Copy** - File copy/move operations
- **File::Path** - Directory creation (make_path)
- **File::Basename** - Path parsing (basename, dirname, fileparse)
- **POSIX** - strftime() for date formatting
- **Data::Dumper** - Debug data structure dumping
- **Archive::Extract** - ZIP file extraction
- **DateTime, DateTime::Duration** - Date/time objects (imported but not heavily used)
- **Text::CSV** - Robust CSV parsing with quote/escape handling
- **Text::Unidecode** - Unicode to ASCII conversion
- **IO::Uncompress::Gunzip** - Gzip decompression
- **IO::Compress::Gzip** - Gzip compression
- **Config::Tiny** - INI file parsing for facility config

### Custom Modules (assumed to exist)
- **PDF::DAO** - Database access object
- **PDF::DpData** - Data structure definitions (HeaderShort, HeaderLong)
- **PDF::DpWriter** - IFF file writer
- **PDF::Parser::BK_LEHS** - LEHS file parser
- **PDF::Formatter** - IFF formatting utilities
- **PDF::DpLoad** - Data loading utilities
- **PDF::Log** - Logging framework
- **PPLOG::PPLogger** - Production planning logger
- **getRefdb()** - Function providing reference database access (must be available in namespace)

### External Scripts
- **read_wksm.pl** - Format specification parser, located via FindBin or specified via -read_wksm_path

---

## Configuration

### Facility Configuration File (INI Format)
Required `-facilityfile` path. Example structure:
```ini
[facility_location]
probe=PROBE_EQUIP_ID
fab6=FAB6_EQUIP_ID
fab8=FAB8_EQUIP_ID
epi=EPI_EQUIP_ID
finalTest=FINAL_TEST_EQUIP_ID
onLotProd=https://ert.url/prod
```

### Format Specification Files
Required in `-fmtdir`. Example naming:
- `product.bcp_fmt` - Product file format
- `operation.bcp_fmt` - Operation file format
- `entity.bcp_fmt` - Entity file format
- `lot_v21.bcp_fmt` - Lot type file format
- `lot_history.bcp_fmt` - Lot history format (most complex)
- `parameter_history.bcp_fmt` - Parameter history format
- `parameter.bcp_fmt` - Parameter groups format
- Similar patterns for other files

---

## Error Handling and Logging

### Error Output Strategy

1. **Valid Records** - Written to primary output files
2. **Invalid Records** - Written to separate `.err` files (same name + ".err" suffix)
   - Same headers and format as valid output
   - Contains records with missing required fields
   - Caused by: missing lots, missing products, validation failures

### Logging Framework
- **PDF::Log** - Main logging system
- **PPLOG::PPLogger** - Production planning logging
- Log levels: DEBUG, TRACE, INFO, WARN, ERROR
- Enabled via `-debug`, `-trace`, `-pplog` flags

### Metadata Lookup Failures
- **Missing lots** - Tracked in %missingLot hash
- **Missing products** - Tracked in %missingProduct hash
- **Fallback strategy** - Use data from input product file if database fails
- **Consequence** - Records sent to error output, not primary output

---

## Special Features and Enhancements

### Silicon Carbide (SiC) Lot Tracking
- Identifies "EPI SLOT" attribute in lot_attr file
- Stores SiC mapping for special FabSite handling
- Supports Maine SiC facility identification

### Multi-Lot Equipment Handling
- FabSite can track multiple lots through same equipment
- Marks as "##MULTI##" lot designation
- Maintains array of lot IDs processed
- Iterates through each lot during output

### Product Filtering
- `-product <regex>` filters output to matching products
- Applied to LEH and FabSite output
- Enables selective data extraction

### Output Forking
- `-fork <directory>` copies output to alternate location
- Useful for multi-facility data distribution
- Works with gzip compression

### Lot Attribute Splitting
- Automatically splits output across files (max 100 lots each)
- Creates `.1.latt`, `.2.latt`, etc. files
- Ensures file size limits

### Character Normalization
- Maps accented and special characters to ASCII
- Prevents encoding issues in downstream systems
- Handles Romanian, Nordic, and European characters

### Rework and Loss Tracking
- Identifies rework vs. loss vs. hold operations
- Differentiates event types (Hold, Release, Scrap)
- Calculates loss aggregates and balances

---

## Performance and Resource Considerations

### Memory Usage
- Large hashes for each major data category
- Potential issues with very large lot histories (millions of records)
- Caching of metadata lookups (lothashes) trades memory for database calls

### File I/O
- Multiple passes through file system
- Temporary extraction and cleanup
- Gzip compression/decompression overhead
- Consider SSD vs. spinning disk performance

### Database Access
- Reference database lookups via getRefdb()
- Cached results reduce repeated queries
- Fallback to input files on failure (reduces dependency)

---

## Revision History Summary

| Date | Author | Key Change |
|------|--------|-----------|
| 25-02-2015 | Jacky | Initial Version |
| 21-05-2015 | Grace | Loss columns addition (_QTY_IN, _TOTAL_LOSS) |
| 28-05-2015 | Grace/Eric | Character cleanup, gunzip support |
| 29-05-2015 | Grace | -v version option |
| 12-06-2015 | S. Boothby | Package lookup during metadata |
| 14-06-2015 | S. Boothby | Text::CSV for entity parsing |
| 07-08-2015 | S. Boothby | Stage as route for loss data |
| 03-09-2015 | S. Boothby | LEH PE entity bug fix |
| 29-09-2015 | S. Boothby | Operation groups to loss output |
| 21-06-2016 | S. Boothby | Text::CSV for phist, vertical tab separators |
| 2020-08-15 | jgarcia | File forking support |
| 2021-04-28 | jgarcia | Colo server setup |
| 2022-05-28 | jgarcia | LEHS support |
| 2023-05-25 | Eric A | PPLogging bug fixes |
| 2023-07-03 | Eric A | ERT URL pass to header |

---

## Known Limitations

1. **Python/Node not available** - Script is Perl-only (no mixed-language processing)
2. **Database dependency** - Requires reference database access via getRefdb()
3. **Format files required** - Must have corresponding .bcp_fmt files for all input types
4. **Single-threaded** - No parallel processing of files
5. **Memory-bound** - Very large archives may exceed available RAM
6. **Character encoding** - Assumes UTF-8 or ASCII input; EBCDIC requires conversion
7. **No recovery** - Partial failures don't allow resume; full rerun required

---

## Related Files

- **scripts/read_wksm.pl** - Format file parser (external dependency)
- **Configuration files** - Facility INI files (required in -facilityfile)
- **Format files** - .bcp_fmt files in -fmtdir (required, one per input file type)
- **PDF::* modules** - Custom library modules (location TBD)
- **Reference database** - Via getRefdb() function (integration point)

---

## Usage Examples

### Basic Processing
```bash
perl fcs_wkstrm.pl \
  -out /data/output \
  -fmtdir /data/formats \
  -loc MAINE \
  /archive/workstream_data.zip
```

### With Product Filtering
```bash
perl fcs_wkstrm.pl \
  -out /data/output \
  -fmtdir /data/formats \
  -loc MAINE \
  -product "ABC.*" \
  /archive/workstream_data.zip
```

### Output Type Selection
```bash
perl fcs_wkstrm.pl \
  -out /data/output \
  -fmtdir /data/formats \
  -loc MAINE \
  -type LEH \
  /archive/workstream_data.zip
```

### Final Lot Test Data
```bash
perl fcs_wkstrm.pl \
  -out /data/output \
  -fmtdir /data/formats \
  -loc MAINE \
  -finallot \
  /archive/workstream_data.zip
```

### With Forking and Grouping
```bash
perl fcs_wkstrm.pl \
  -out /data/output \
  -fmtdir /data/formats \
  -loc MAINE \
  -fork /network/share \
  -lehgroup \
  /archive/workstream_data.zip
```

---

## Script Variants

### fcs_wkstrm_lim_by_date.pl vs fcs_wkstrm.pl

The **fcs_wkstrm_lim_by_date.pl** variant extends the base script with limit date tracking and database integration functionality. Key differences:

#### New Subroutines (lim_by_date variant only)

**getPSVerLimitDate(program_name, parameter_set, parameter_set_version)**
- Retrieves or creates parameter set version limit dates from reference database
- Integrates with `%limits` hash for caching
- Calls `getRefdb->checkAndInsertLimitGetInfo()` to register new limits
- Returns the effective date for a parameter set version (when it was first seen or registered)
- Used to populate FabSite and offline metrology output with limit dates

**addTestInfo(parameter_set, parameter_set_version, date_stamp, test_name, test_units, test_low_limit, test_high_limit)**
- Adds or updates test parameter information into `%parameter_sets` hash
- Creates/updates nested hash structure: `{parameter_set~~~version}{test_name}`
- Stores YMS PSET Start Date metadata
- Prevents duplicate test entries within same parameter set version
- Enables parameter history enrichment with test metadata

#### Enhanced Data Structures (lim_by_date variant)

**%parameter_sets** (expanded)
- Key: `parameter_set~~~parameter_set_version` (e.g., "WB-CSPL-L~~~REV1")
- Value: Hash containing test information
  - Special key: `YMS PSET Start Date` → parameter set start date
  - Test keys: Each test_name maps to test object with properties:
    - name, units, LSL (low shutdown limit), HSL (high shutdown limit)

**%limits** (new)
- Key: `program_name~~~parameter_set_version` (e.g., "FS::TEST_010_Description::WB-CSPL-L::MAINE::WKS~~~REV1")
- Value: Limit object with properties:
  - DATE: Effective date when limit was first registered
  - PROGRAM: Program name for tracking
  - REVISION: Parameter set version
  - input_file: Basename of input ZIP file for audit trail

#### Modified Subroutines

**OutputFabSiteLine()** (lim_by_date: calls getPSVerLimitDate)
- Enhanced to include limit date in FabSite output
- Constructs program name dynamically for limit lookup
- Adds date as parameter set revision reference to output

**OutputMetOffLine()** (lim_by_date: calls getPSVerLimitDate)
- Similar enhancement for offline metrology output
- Uses `FSNL::` prefix for offline metrology program names

**ProcessPhistFile()** (lim_by_date: calls addTestInfo)
- Extracts test metadata (name, units, limits) from parameter history
- Populates `%parameter_sets` hash with test information
- Records parameter set start date for limit date tracking

#### Integration Points

Both variants use `getRefdb()` for database access but with different purposes:
- **Base (fcs_wkstrm.pl)**: Only metadata lookup (lots, products)
- **lim_by_date**: Adds limit registration (`checkAndInsertLimitGetInfo()`)

#### Output Impact

The lim_by_date variant adds limit date information to:
1. **FabSite (FS) files** - `lim_date` column populated with parameter set registration date
2. **Offline Metrology (OFF) files** - Same `lim_date` column addition
3. **Parameter history tracking** - Maintains test definition history

#### Use Case

**fcs_wkstrm_lim_by_date.pl** is designed for environments requiring:
- Traceability of when parameter set limits were first seen/registered
- Audit trail of limit definitions over time
- Reference database integration for limit history
- Historical analysis of test parameter definitions

---

**Document Version:** 1.1  
**Last Updated:** 2024-07-14  
**Applicable Script Version:** fcs_wkstrm.pl v1852+, fcs_wkstrm_lim_by_date.pl (variant)
