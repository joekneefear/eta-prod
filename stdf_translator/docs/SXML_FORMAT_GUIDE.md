# Enhanced STDF to SXML Translator

## Overview

This enhanced version of the STDF translator now fully supports the **SXML format** (Standardized XML format for STDF data) as used by the Java encoder/decoder. The translator dynamically includes all relevant sections that exist in the source STDF file.

## Java Entities Mapping

The translator now supports all SXML entity types:

| Java Entity | STDF Source | XML Element | Included When |
|------------|------------|------------|---------------|
| `File` | FAR | `<File>` | Always (root) |
| `Audits` | ATR | `<Audits><Audit>` | ATR records exist |
| `Lot` | MIR | `<Lot>` | Always |
| `Sites` | GDR | `<Sites><Site>` | GDR records exist |
| `Pins` | GDR | `<Pins><Pin>` | GDR records exist |
| `Wafers` | WIR/WRR | `<Wafers><Wafer>` | Wafer records exist |
| `Units` | PIR/PRR | `<Units><Unit>` | Unit records exist |
| `Test` | PTR/FTR/MPR | `<Test>` | Test records exist |
| `Result` | PRR | `<Result>` | Always (per unit) |

## SXML Hierarchy

The output follows this exact hierarchy:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Xml>
  <File FileName="..." CPUType="2" STDFVersion="4">
    <Audits>
      <Audit CMDLine="..." ModificationTime="..." />
      ...
    </Audits>
    
    <Lot PartType="..." OperatorName="..." ... >
      <Sites>
        <Site Site="0" Head="1" SiteCount="1" />
        ...
      </Sites>
      
      <Pins>
        <Pin Site="0" PinName="..." LogicalPinName="..." />
        ...
      </Pins>
      
      <Wafers>
        <Wafer WaferId="..." StartTime="...">
          <Units>
            <Unit Head="..." Site="..." PartId="...">
              <Test TestNum="..." TestName="..." Value="..." PF="..." Min="..." Max="..." Units="..." />
              ...
              <Result X="..." Y="..." HardBin="..." SoftBin="..." TestTime="..." />
            </Unit>
            ...
          </Units>
        </Wafer>
        ...
      </Wafers>
    </Lot>
  </File>
</Xml>
```

## Key Implementation Details

### 1. **Two-Pass Processing**
- **Pass 1**: Scans all records to determine which sections exist (Audits, Sites, Pins, etc.)
- **Pass 2**: Emits XML in proper order, only including sections that have data

### 2. **Dynamic Section Inclusion**
Sections are only emitted if they exist in the source STDF:
- **Audits**: Only if ATR (Audit Trail) records are present
- **Sites & Pins**: Only if GDR (Generic Data Record) records are present
- **Wafers/Units/Tests**: Only if corresponding STDF records exist

### 3. **Proper XML Nesting**
The translator uses a state machine to track open tags and closes them in the correct order:
```
Xml > File > Audits > (closed)
Xml > File > Lot > Sites > (closed)
Xml > File > Lot > Pins > (closed)
Xml > File > Lot > Wafers > Wafer > Units > Unit > (Tests) > Result > (closed)
```

### 4. **STDF Record Mapping**

| STDF Record | Maps To | Attributes |
|------------|---------|-----------|
| **FAR** | `<File>` | FileName, CPUType, STDFVersion |
| **MIR** | `<Lot>` | PartType, OperatorName, TesterType, NodeName, TestCode, StartTime, JobName, FloorId, JobRevision, LotId, TestTemperature, SublotId, SetupTime, AUXFile |
| **ATR** | `<Audit>` | CMDLine, ModificationTime, Id |
| **GDR** | `<Site>`, `<Pin>` | Site-specific and Pin-specific attributes |
| **WIR** | `<Wafer>` | WaferId, StartTime |
| **WRR** | (closes wafer) | - |
| **PIR** | `<Unit>` | Head, Site, PartId |
| **PTR** | `<Test>` | TestNum, TestName, Value, PF, Min, Max, Units |
| **FTR** | `<Test>` | TestNum, TestName, PF |
| **MPR** | `<Test>` | TestNum, TestName, PF |
| **PRR** | `<Result>` | X, Y, HardBin, SoftBin, TestTime |
| **MRR** | (closes lot) | - |

## Features

✅ **Conditional Section Inclusion** - Only includes sections present in source STDF  
✅ **Proper XML Structure** - Valid, well-formed XML matching SXML standard  
✅ **Streaming Support** - Can be used with large files (memory-efficient)  
✅ **Type Safety** - Rust type system prevents many common errors  
✅ **Comprehensive Attributes** - Maps all major STDF fields to XML attributes  
✅ **CLI & Web Service** - Works with both command-line and web server modes  

## Usage

### CLI Mode
```bash
cargo run --release -- --input sample.stdf --output output.xml
```

### Web Service Mode
```bash
cargo run --release -- --server
# Then POST to http://localhost:3000/convert
```

## Limitations & TODOs

1. **GDR Parsing** - Sites and Pins sections are placeholder implementations
   - TODO: Parse actual GDR data to extract site/pin information
   
2. **Timestamp Formatting** - Currently outputs raw Unix timestamps
   - TODO: Use `chrono` crate to format as ISO 8601 dates
   
3. **TestInfo** - Test metadata consolidation not yet implemented
   - TODO: Cache TSR records to merge with PTR/FTR/MPR test data
   
4. **Error Handling** - Current implementation continues on malformed records
   - TODO: Add logging/warnings for skipped or problematic records

## Testing

To verify the enhanced translator:

1. **Build the project**:
   ```bash
   cargo build --release
   ```

2. **Convert a sample STDF file**:
   ```bash
   cargo run --release -- --input sample.stdf --output output.xml
   ```

3. **Verify the XML structure**:
   - Check that sections match expected hierarchy
   - Confirm only sections with data are included
   - Validate XML syntax with xmllint or browser

4. **Compare with Java encoder output**:
   - Both should have identical XML structure
   - Attribute names and ordering should match

## References

- **SXML Format**: Defined in Java encoder at `encoder-testdata-xml/src/main/java/com/onsemi/encoder/testdata/xml/entities/sxml/`
- **STDF Specification**: Based on rust-stdf library's STDF record definitions
- **Sample Format**: See `docs/sxml_sample_format.sxml.xml`

