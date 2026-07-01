# JND Probe Tesec WMC Enricher - Process Documentation

## Overview

The `jnd_probe_tesec_wmc_enricher.py` script processes and enriches SXML (Semiconductor XML) files from JND probe Tesec testing with metadata from multiple sources, then outputs an enriched XML file with complete lot/production metadata and wafer map information.

## Overall Process Flow

The script takes a raw SXML file from JND probe Tesec testing and enriches it with metadata from multiple sources, then outputs an enriched XML file.

## Key Processing Steps

### 1. Input Parsing & Initial Extraction

```python
tesec_sxml_parser = SxmlParser(input_file)
stdml_lot_section, model = tesec_sxml_parser.get_lot_attributes_and_units()
```

- Parses the input SXML file
- Extracts lot attributes: `LotId`, `SublotId` (wafer number), `UserText`, `JobName`
- Builds a data model with wafer statistics

### 2. Metadata Collection from Multiple Sources

The script gathers metadata from 4 primary sources:

#### a) Lot Metadata File (`.lot` files)

```python
lot_metadata, last_lot_metadata = JndUtil.load_jnd_lot_metadata(lot_metadata_file_fullpath)
```

**Contains:**
- TPNO (product)
- ParentLot
- LotType
- Fab
- SourceLot
- Process
- Technology

**Purpose:** Fallback when web service data is unavailable

#### b) RefDB Web Service (ERT system)

```python
onlotprod_url = f"{ws_urls['onlotprod']}/{raw_lot}"
onlotprod_metadata = refdb_api_client.get_metadata(onlotprod_url, default_onlot_prod, ws_timeout)
```

**Returns:**
- `onLot` structure (lot-level metadata)
- `onProd` structure (product-level metadata)

**Purpose:** Primary source for lot and product metadata

#### c) Scribe Reference Files

```python
waferid = JndUtil.get_waferid_scribe_file(raw_lot, raw_wafer_number, waferids)
```

**Contains:**
- Mapping of lot + wafer number to physical wafer scribe IDs
- Merges regular scribe and ship scribe dictionaries

**Purpose:** Provides physical wafer identification

#### d) FJM Files (Foundry Job Mask files)

```python
fjm_wmc_generator = FJMParser(fjm, wmap)
wmc_dictionary = fjm_wmc_generator.get_wmc_in_dictionary()
```

**Contains:**
- Wafer map coordinates (WMC)
- Mask set information
- Die layout information

**Purpose:** Provides wafer map geometry and mask data

**Note:** TPNO extracted from filename or JobName is used to locate the FJM file

### 3. Metadata Hierarchy & Fallback Logic

The script implements a priority system for each metadata type:

#### For Technology:
1. RefDB web service
2. Lot metadata file
3. Mark as no metadata (sandbox routing)

#### For Wafer ID:
1. Scribe reference file
2. RefDB web service
3. UserText attribute (for EQ lots)
4. Calculated wafer ID (sandbox routing)

#### For TPNO (Product):
1. Filename extraction
2. JobName parsing (EQ lots)
3. Lot metadata file

### 4. Metadata Combination & Mapping

```python
combined_metadata = {
    **onlotprod_metadata,  # onLot, onProd structures
    'onScribe': onscribe_metadata,
    'stdml': stdml_lot_section,
    'constant': constant_mapping_data,
    'wmc': wmc_dictionary
}
```

The `MetadataDTO` class uses YAML-defined mappings:
- **field_mapping**: Defines which source field maps to which output field
- **source_mapping**: Tracks the origin of each metadata value

### 5. XML Enrichment

```python
metadataDTO_instance = MetadataDTO(field_mapping=field_mapping, source_mapping=source_mapping)
metadata = metadataDTO_instance.generate_metadata_xml(combined_metadata)
tesec_sxml_enricher = SxmlEnricher(input_file)
enriched_tesec_xml = tesec_sxml_enricher.enrich_xml(metadata)
```

The enricher injects the combined metadata into the original SXML structure.

### 6. Wafer Map Enrichment

```python
stats = model.wafers[0].stats()
wmap = Wmap(stats)
wmap.wf_units = yaml_data['Tesec']['WmcWaferUnits']
wmap.flat = yaml_data['Tesec']['WmcWaferFlat']
wmap.flat_type = yaml_data['Tesec']['WmcFlatType']
wmap.positive_x = yaml_data['Tesec']['WmcPositiveX']
wmap.positive_y = yaml_data['Tesec']['WmcPositiveY']
```

**Wafer map data includes:**
- Die coordinates (center_x, center_y from FJM)
- Wafer orientation (flat position, positive X/Y directions)
- Physical units
- Mask set information

### 7. Output & Routing Logic

```python
writer_instance.noMeta = True  # Routes to SANDBOX
writer_instance.noWMap = True  # Indicates missing wafer map
```

The script sets flags that determine data routing:

**Production schema:** Complete metadata with valid Technology, scribe ID, and wafer map

**Sandbox schema:** Missing critical metadata (invalid TPNO, no scribe, calculated wafer IDs)

## Special Handling

### EQ Lots (Engineering lots starting with "EQ")

- Extract TPNO from JobName field instead of filename
- Use UserText attribute as fallback for wafer scribe ID

```python
if raw_lot.startswith('EQ'):
    recipe_from_stdf = str(stdml_lot_section.get('JobName')).upper()
    get_tpno_from_device = lambda recipe_from_stdf: str(recipe_from_stdf.split('-')[1].split('_')[0].split('.')[0]) if '-' in recipe_from_stdf else "Invalid format"
    tpno = get_tpno_from_device(recipe_from_stdf)
```

### 7G Lots (specific lot format)

- Converts to JM lot format for RefDB lookup
- Special TPNO extraction logic (characters 2-7)

```python
if raw_lot.startswith('7G'):
    jm_lot = JndUtil.jnd_7G_to_jm(raw_lot)
    if jm_lot:
        onlotprod_url = f"{ws_urls['onlotprod']}/{jm_lot}"
```

## Data Quality Tracking

The `source_mapping` dictionary tracks metadata provenance:

```python
source_mapping["onLot"]["product"] = "SCRIPT_LOT_METADATA"
source_mapping["onScribe"]["waferId"] = "SCRIPT_SCRIBE_REF_FILE"
source_mapping["onProd"]["technology"] = "SCRIPT_LOT_METADATA"
```

This enables downstream systems to understand data lineage and quality.

## Metadata Structure

### Combined Metadata Dictionary

```
combined_metadata
├── onLot
│   ├── lot
│   ├── product (TPNO)
│   ├── parentLot
│   ├── lotType
│   ├── fab
│   ├── sourceLot
│   └── status
├── onProd
│   ├── process
│   ├── technology
│   └── maskSet
├── onScribe
│   ├── lot
│   ├── waferNum
│   ├── waferId
│   ├── scribeId
│   └── status
├── stdml (from SXML file)
│   ├── LotId
│   ├── SublotId
│   ├── UserText
│   └── JobName
├── constant (from YAML config)
│   └── [various constant values]
└── wmc (from FJM file)
    ├── center_x
    ├── center_y
    └── maskSet
```

## Error Handling & Validation

### Critical Validations

1. **TPNO Validation**: Must be alphanumeric and at least 4 characters
2. **Wafer Number Validation**: Must be numeric
3. **Scribe ID Validation**: Must exist or be derivable
4. **Technology Validation**: Must be present for production routing

### Sandbox Routing Triggers

Files are routed to SANDBOX when:
- Invalid or missing TPNO
- No scribe information available
- Calculated wafer IDs (not from reference files)
- Missing Technology information
- Missing wafer map center coordinates

## Output

### Final Output File

```python
sxml_instance = SXML(writer=writer_instance, sxml=enriched_tesec_xml)
sxml_instance.write_list_of_line_string_to_file()
```

- Format: Enriched XML (gzipped)
- Extension: `.xml.gz`
- Location: Specified outbox directory
- Contains: Original test data + enriched metadata + wafer map information

### Side Effects

```python
if new_waferids:
    JndUtil.append_to_jnd_scribe_file_if_not_exists(new_waferids, scribe_file)
```

New wafer IDs discovered during processing are appended to the scribe reference file for future use.

## Configuration

The script relies on a YAML configuration file (`JND_CONFIG.yaml`) containing:

- File paths (scribe files, lot metadata, FJM location)
- Web service URLs
- Field mappings
- Constant values
- Wafer map parameters
- Retry/timeout settings

## Dependencies

### Key Libraries
- `SxmlParser`: Parses SXML input files
- `SxmlEnricher`: Enriches SXML with metadata
- `FJMParser`: Extracts wafer map from FJM files
- `RefdbAPIClient`: Queries RefDB web services
- `JndUtil`: JND-specific utility functions
- `MetadataDTO`: Metadata transformation and mapping
- `Writer`: Output file management
- `PPLogger`: Process logging

## Logging

The script provides detailed logging at each step:
- Metadata source identification
- Fallback logic execution
- Validation failures
- Routing decisions (production vs sandbox)

Log file location: `$DPLOG/<script_name>.log`
