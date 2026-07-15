# FCS_WKSTRM Script Variants - Easy Comparison Guide

Think of these three scripts as **three versions of the same tool**, each adding more features on top of the previous one.

---

## Quick Overview Table

| Feature | fcs_wkstrm_orig.pl | fcs_wkstrm.pl | fcs_wkstrm_lim_by_date.pl |
|---------|-------------------|---------------|--------------------------|
| **Release Date** | June 2016 | 2020-2023 | Latest variant |
| **Main Job** | Extract & transform workstream data | Extract & transform workstream data | Extract & transform + track limit dates |
| **Output Files** | LEH, FS, LOSS, LOTEVENT, LATT, EHIST | LEH, FS, LOSS, LOTEVENT, LATT, EHIST, LEHS | Same as fcs_wkstrm.pl |
| **Database Features** | Basic lot lookup | Basic lot lookup | Lot lookup + **Limit date tracking** |
| **Complexity** | Simplest | Medium | Most advanced |

---

## What Each Script Does (Simplified)

### Script 1: fcs_wkstrm_orig.pl (Original - 2016)
**Use this if:** You just need to convert manufacturing data to standard formats.

**What it does:**
- Reads compressed ZIP files with manufacturing test data
- Extracts and organizes the data
- Looks up product information from a database
- Creates output files in multiple formats (LEH, FS, LOSS, etc.)

**Main files created:**
- LEH (Lot Event History) - who processed the lot and when
- FS (FabSite) - test results from equipment
- LOSS - scrap and rework data
- LATEVENT - lot status changes
- LATT - lot attributes
- EHIST - equipment/entity history

**Special features:**
- Handles Silicon Carbide (SiC) lot tracking
- Cleans up special characters (accents, symbols)
- Can filter output by product name

---

### Script 2: fcs_wkstrm.pl (Improved - 2020-2023)
**Use this if:** You need all the original features PLUS LEHS support and better organization.

**Everything from Script 1, PLUS:**

**New output file type:**
- **LEHS (Lot Event History with Steps)** - Advanced lot tracking with process step details

**New features:**
- PPLogger support (Production Planning logging)
- Better error handling and logging
- Support for facility configuration files
- Output file grouping by program hierarchy
- File forking to alternate directories
- Better handling of multi-lot equipment

**Key improvement:**
- Adds `processLehWithStep()` function that handles complex lot event history with step information
- Uses `PDF::Parser::BK_LEHS` module for advanced parsing

---

### Script 3: fcs_wkstrm_lim_by_date.pl (Advanced - Latest)
**Use this if:** You need to track WHEN test limits were first registered in the database.

**Everything from Script 2, PLUS:**

**New tracking capability:**
- **Limit date tracking** - Records when each test parameter limit was first seen/registered

**How it works:**
1. As the script processes parameter data, it records test limits
2. For each unique limit, it checks/records the date it was first registered
3. This date is stored in a database via `getRefdb->checkAndInsertLimitGetInfo()`
4. The date is added to output files for audit trail purposes

**New functions:**
- `getPSVerLimitDate()` - Gets or creates limit registration dates
- `addTestInfo()` - Records test parameter metadata

**Enhanced output:**
- FabSite (FS) files now include `lim_date` column
- Offline Metrology (OFF) files now include `lim_date` column
- Full audit trail of when limits were registered

---

## Side-by-Side Feature Comparison

### Data Processing
```
ORIG:  Read ZIP → Parse files → Look up metadata → Output
       ↓
NORMAL: Read ZIP → Parse files → Look up metadata → Output + LEHS support
       ↓
LIM_BY_DATE: Read ZIP → Parse files → Look up metadata → Track limit dates → Output
```

### Database Interactions
```
ORIG:
  - getRefdb->getMetaData(lot)              [What is this lot?]

NORMAL:
  - getRefdb->getMetaData(lot)              [What is this lot?]
  - getRefdb->getBKLEHSmetadata(lot)        [Get advanced lot info]

LIM_BY_DATE:
  - getRefdb->getMetaData(lot)              [What is this lot?]
  - getRefdb->checkAndInsertLimitGetInfo()  [Register/track limit dates]
```

### Key Hashes (Data Storage)
```
ORIG & NORMAL:
  %lhistinfo          → Lot history data
  %phistinfo          → Parameter history
  %limits             → (exists but minimal use)

LIM_BY_DATE (adds):
  %parameter_sets     → Test information keyed by "parameter_set~~~version"
  %limits             → Expanded to track limit registration dates
```

---

## When to Use Each Script

### Use **fcs_wkstrm_orig.pl** if:
- ✅ You have older code/systems that depend on it
- ✅ You don't need LEHS support
- ✅ You want the simplest, most stable version
- ❌ You need limit date tracking

### Use **fcs_wkstrm.pl** if:
- ✅ You need LEHS (Lot Event History with Steps) support
- ✅ You want the most common, well-maintained version
- ✅ You need PPLogger integration
- ✅ You need file forking capabilities
- ❌ You need to track when limits were registered in the database

### Use **fcs_wkstrm_lim_by_date.pl** if:
- ✅ You need complete audit trail of limit registration dates
- ✅ You want to track when each test limit was first seen
- ✅ Your organization requires limit history for compliance
- ✅ You're integrating with a reference database that tracks limits
- ✅ You need `lim_date` column in FS and OFF output files

---

## Command Line Examples

All three scripts use the same basic command structure:

```bash
perl fcs_wkstrm.pl \
  -out /path/to/output \
  -fmtdir /path/to/format/files \
  -loc MAINE \
  /path/to/data.zip
```

### With Optional Parameters

```bash
# Filter by product
perl fcs_wkstrm.pl -out /out -fmtdir /fmt -loc MAINE -product "ABC.*" data.zip

# Output specific file types only
perl fcs_wkstrm.pl -out /out -fmtdir /fmt -loc MAINE -type LEH data.zip

# Group LEH files by program
perl fcs_wkstrm.pl -out /out -fmtdir /fmt -loc MAINE -lehgroup data.zip

# Fork output to alternate location
perl fcs_wkstrm.pl -out /out -fmtdir /fmt -loc MAINE -fork /network/share data.zip
```

---

## Output File Comparison

### Files Created by All Three Scripts

| File Type | Description | Format |
|-----------|-------------|--------|
| LEH | Lot Event History | IFF (Internal File Format) |
| FS | FabSite - Test results | IFF with vertical tab separators |
| LOSS | Scrap/rework tracking | IFF |
| LOTEVENT | Lot status events | CSV |
| LATT | Lot attributes | Tab-separated |
| EHIST | Equipment history | CSV |
| ENT | Entity catalog | CSV |

### Additional Files by fcs_wkstrm.pl

| File Type | Description | Format |
|-----------|-------------|--------|
| LEHS | Lot Event History with Steps | IFF |

### Columns Added by fcs_wkstrm_lim_by_date.pl

For **FS** and **OFF** output:
- `lim_date` - Date when the parameter set limit was first registered

---

## Key Differences in Code

### Function Additions

**fcs_wkstrm.pl adds:**
- `processLehWithStep()` - Processes LEHS files with advanced lot tracking

**fcs_wkstrm_lim_by_date.pl adds:**
- `getPSVerLimitDate()` - Retrieves/creates limit dates from database
- `addTestInfo()` - Records test parameter metadata

### Data Handling

**Original version:**
- Simple metadata lookup (lot ID → product info)

**Standard version:**
- Same metadata lookup
- Additional LEHS file parsing

**Lim_by_date version:**
- Same as standard
- **PLUS** tracks when each test limit was registered
- **PLUS** stores parameter set information with test metadata

---

## Common Questions

### Q: Can I switch between versions?
**A:** Yes, they're mostly compatible. Output format is the same. The lim_by_date variant just adds optional columns and database tracking.

### Q: Will the lim_by_date version produce different output?
**A:** Only if you look at the extra columns (`lim_date`). Otherwise, the core data is identical.

### Q: Do I need the reference database for all three?
**A:** Yes, all three use `getRefdb()` for lot metadata. The lim_by_date version makes additional database calls for limit tracking.

### Q: Which version should our team use?
**A:** Start with `fcs_wkstrm.pl` (standard). Only switch to lim_by_date if you need limit registration tracking for audit/compliance.

---

## Version History Summary

```
June 2016 → fcs_wkstrm_orig.pl (Initial release)
           ↓ (Added LEHS support, PPLogger, better features)
2020-2023 → fcs_wkstrm.pl (Current standard)
           ↓ (Added limit date tracking)
Latest    → fcs_wkstrm_lim_by_date.pl (For organizations needing limit audit trail)
```

---

**Document Version:** 1.0  
**Created:** July 14, 2026  
**For Users:** Beginners to Intermediate  
**Difficulty:** Easy to understand
