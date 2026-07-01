# n_getDWProductMetadata.sh - Reference Documentation

## Overview

`n_getDWProductMetadata.sh` extracts product reference data from Snowflake. This script replaced the Oracle-based `getDWProductMetadata.sh` and queries all data, including SITE_DIM, directly from Snowflake.

**Created**: 15-Jul-25 by NT  
**Purpose**: Transform the script to work with Snowflake query provided by Scott

## Usage

```bash
./n_getDWProductMetadata.sh <db-user> <db-password> <db-sid>
```

### Arguments

1. **db-user**: Snowflake username
2. **db-password**: Snowflake password  
3. **db-sid**: Snowflake ODBC DSN (e.g., `MART_SNOWFLAKE`)

### Environment Variables

- `REFERENCE_DATA_DIR`: Must be set to a valid directory for output files

### Example

```bash
export REFERENCE_DATA_DIR=/apps/exensio_data/reference_data
./n_getDWProductMetadata.sh $SNOW_USER $SNOW_PASS MART_SNOWFLAKE
```

## Output

### File Location

- **Output**: `$REFERENCE_DATA_DIR/DWProductDimProductInfo-<timestamp>.prod`
- **Archive**: `/apps/exensio_data/archives-yms/reference_data/product/`
- **Log**: `$REFERENCE_DATA_DIR/log/n_getDWProductMetadata.sh.<timestamp>.log`

### Output Format

Pipe-delimited file with header:
```
PRODUCT|ITEM_TYPE|FAB|FAB_DESC|AFM|PROCESS|FAMILY|PACKAGE|GDPW|WF_UNITS|WF_SIZE|DIE_UNITS|DIE_WIDTH|DIE_HEIGHT|LAST_CHANGED_DATE
```

**Columns**:
- `PRODUCT`: Product identifier (dashes replaced with underscores)
- `ITEM_TYPE`: Part type (FG, DIE, WAFER, MSLC, EPI)
- `FAB`: Manufacturing area code (from SITE_DIM)
- `FAB_DESC`: Manufacturing area description (from SITE_DIM) ⭐
- `AFM`: Always blank
- `PROCESS`: Legacy part description
- `FAMILY`: Device family
- `PACKAGE`: Package type
- `GDPW`: Good die per wafer (PDPW_VALUE)
- `WF_UNITS`: Wafer units (always 'MM')
- `WF_SIZE`: Wafer size
- `DIE_UNITS`: Die units (always 'MC')
- `DIE_WIDTH`: Die width with scribe
- `DIE_HEIGHT`: Die height with scribe
- `LAST_CHANGED_DATE`: Last change date (DD-MON-YY format)

## Snowflake Data Sources

### Primary Schema

- **Warehouse**: `application_prd_wh`
- **Role**: `APPLICATIONPRD_MFG_CONSUMER_RO`
- **Main Schema**: `ANALYTICSPRD.ENTERPRISE`

### Tables Used

1. **PART_DIM** (`ANALYTICSPRD.ENTERPRISE.PART_DIM`)
   - Product information, part types, dimensions
   
2. **SITE_DIM** (`ANALYTICSPRD.ENTERPRISE.SITE_DIM`) ⭐
   - Manufacturing area codes and descriptions
   - Columns: `MFG_AREA_CODE`, `MFG_AREA_DESCRIPTION`, `FRONTEND_BACKEND_FLAG`
   
3. **get_supply_path_end_part_component_site** (`applicationprd.mfg.get_supply_path_end_part_component_site`)
   - Bill of materials and supply path information

## SITE_DIM Integration

### How SITE_DIM is Used

The script joins to `ANALYTICSPRD.ENTERPRISE.SITE_DIM` in the `get_fab` CTE:

```sql
inner join ANALYTICSPRD.ENTERPRISE.SITE_DIM COMPONENT_sd
    on COMPONENT_sd.MFG_AREA_CODE = WU.BOM_COMPONENT_MFG_AREA_CODE
    and COMPONENT_sd.FRONTEND_BACKEND_FLAG = WU.BOM_COMPONENT_FRONTEND_BACKEND_FLAG
```

### Data Retrieved

- **MFG_AREA_CODE**: Manufacturing area code (e.g., 'UWA', 'BK', 'CP')
- **MFG_AREA_DESCRIPTION**: Human-readable description (e.g., 'Wafer Fab - Gresham', 'Backend - Bucheon')
- **FRONTEND_BACKEND_FLAG**: 'F' for front-end, 'B' for back-end

### Output Mapping

The SITE_DIM data appears in the output as:
- `FAB` column = `MFG_AREA_CODE`
- `FAB_DESC` column = `MFG_AREA_DESCRIPTION` (truncated to 50 characters)

## Query Structure

### Main CTEs

1. **bom_type**: Ranks part sub-types to determine primary part type
2. **get_fab**: Retrieves FAB information including SITE_DIM join ⭐
3. **get_fam**: Gets legacy part descriptions
4. **get_pkg_cfg**: Extracts package configuration
5. **get_prod**: Main product data assembly
6. **res**: Final result aggregation

### Special Features

- **UWA Wafer Suffix**: Products from UWA fab with FAB part type get `_WAFER` suffix
- **Product Normalization**: Dashes replaced with underscores
- **Part Type Ranking**: WAFER > DIE > FG for deduplication

## Connection Details

### ODBC Connection

Uses `isql` command-line tool:
```bash
isql ${snow_sid} ${snow_user} ${snow_pass} -b -n -dx -x0x20
```

**Flags**:
- `-b`: Batch mode (no prompts)
- `-n`: Remove column numbers
- `-dx`: Delimiter mode
- `-x0x20`: Use space (0x20) as delimiter

### Post-Processing

The script cleans up the output:
```bash
sed -i '/SQLRowCount/d; /+-----------------/d; /IFNULL/d' ${outFileTmp}
```

Removes:
- SQLRowCount lines
- Separator lines (`+---`)
- IFNULL function names

## Differences from Oracle Version

| Aspect | Old (Oracle) | New (Snowflake) |
|--------|--------------|-----------------|
| Database | Oracle DW | Snowflake |
| SITE_DIM | `BIWMARTS.SITE_DIM` | `ANALYTICSPRD.ENTERPRISE.SITE_DIM` |
| Connection | `sqlplus` | `isql` (ODBC) |
| Arguments | 4-5 args | 3 args |
| Product Filter | Regex patterns (0-9, A-M, N-Z) | No filter (all products) |
| Wafer Suffix | Optional 5th argument | Built into query logic |

## Troubleshooting

### Common Issues

1. **REFERENCE_DATA_DIR not set**
   ```
   Environment variable REFERENCE_DATA_DIR must be set to a valid directory
   ```
   **Solution**: `export REFERENCE_DATA_DIR=/path/to/directory`

2. **ODBC Connection Failure**
   - Verify Snowflake ODBC driver is installed
   - Check DSN configuration in `odbc.ini`
   - Verify credentials

3. **Empty FAB_DESC**
   - Check if SITE_DIM has data for the MFG_AREA_CODE
   - Verify FRONTEND_BACKEND_FLAG matches

### Debug Mode

The script has a debug exit at line 339:
```bash
echo ${tmpScript}
exit 1
```

**To enable normal operation**: Comment out or remove the `exit 1` line.

## Performance Considerations

- **Query Complexity**: High - multiple CTEs with window functions
- **Expected Runtime**: Varies based on data volume (typically 5-30 minutes)
- **Warehouse Size**: Uses `application_prd_wh` - ensure adequate compute resources

## Maintenance

### When to Update

- SITE_DIM schema changes in Snowflake
- New part sub-types added
- Output format requirements change
- Performance optimization needed

### Related Scripts

- **Old Version**: `scripts/getDWProductMetadata.sh` (Oracle-based, deprecated)
- **Similar Pattern**: `scripts/getSnowflakeE142ModuleTrace.pl` (Snowflake ODBC example)

## Security

- **Credentials**: Passed as command-line arguments (consider using environment variables)
- **Output Files**: Created with default permissions in `$REFERENCE_DATA_DIR`
- **Archive**: Compressed with gzip before archiving

## Notes

- The script currently has `exit 1` after the query execution (line 339), preventing file archiving
- Remove this debug line for production use
- The query returns all products (no filtering by product name pattern like the old script)
