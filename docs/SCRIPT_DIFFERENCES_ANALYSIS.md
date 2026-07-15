# FCS_WKSTRM.PL - Differences Between Current and Original Versions

## Overview
This document details the functional differences between `fcs_wkstrm.pl` (current version) and `fcs_wkstrm_orig.pl` (original version). The current version includes significant enhancements for production data handling and output flexibility.

---

## Major Changes

### 1. Facility Configuration Handling

#### Original Approach
```perl
if ($hOptions{FINALLOT}) {
    $equip6_id = $config->{$location}->{finalTest};
} elsif ($hOptions{FAB8}) {
    $equip6_id = $config->{$location}->{fab8};
} elsif ($hOptions{FAB6}) {
    $equip6_id = $config->{$location}->{fab6};
} elsif ($hOptions{EPI}) {
    $equip6_id = $config->{$location}->{epi};
} else {
    $equip6_id = $config->{$location}->{probe};
}
```

#### Current Approach
```perl
$pp_method = "BY_PRODUCT";
if (defined($hOptions{method}))
{
   if ( $hOptions{method} eq "BY_PROGRAM" )
   {
      $pp_method = "BY_PROGRAM";
   }
}

$facilityArea = $hOptions{FACILITYAREA};
if($facilityArea =~ /fab8/i) {
    $equip6_id = $config->{$location}->{fab8};
} elsif($facilityArea =~ /fab6/i) {
    $equip6_id = $config->{$location}->{fab6};
} elsif($facilityArea =~ /probe/i) {
    $equip6_id = $config->{$location}->{probe};
} elsif($facilityArea =~ /epi/i) {
    $equip6_id = $config->{$location}->{epi};
} elsif($facilityArea eq "") {
    dpExit(1,"Cant get FACILITY AREA which is a mandatory argument.");
}
```

**Changes:**
- Removed `FINALLOT` boolean flag approach
- Added mandatory `-facilityarea` parameter (replaces boolean flags)
- Introduced `-method` option for output organization strategy
- Made facility area case-insensitive (case-insensitive regex matching)
- Added explicit error message when facility area is missing

---

### 2. Output Organization Method

#### New Feature: Production Planning Method Selection

**Location Code:** Variable `$pp_method` added at global scope

**Impact on FabSite Output:**

##### BY_PRODUCT (Default)
- File naming: `filename_product-lot`
- Header included in output
- Output structure remains traditional

##### BY_PROGRAM (New)
- File naming: `filename_parameter_set_id`
- Dynamic header handling (header only for first output, not for error output)
- Enhanced column headers include product family, process, and package info
- Columns added to output: family, process, package

**Code Implementation:**
```perl
my $progName="FS::" .  $lhistfsinfo{$lhistfskey}{'operation'} .
    "_" .  $operinfo{$operkey}{'short_description'} .
    "::" .  $phistinfo{$holder}{'parameter_set_id'} .
    "::" .  $lhistfsinfo{$lhistfskey}{'facility'} . "::WKS";

if ( $pp_method eq "BY_PROGRAM" )
{
    # Additional columns in output
    $newline .=  "\cK".FormatField($lhistfsinfo{$lhistfskey}{'family'})
        ."\cK".FormatField($lhistfsinfo{$lhistfskey}{'process'})
        ."\cK".FormatField($lhistfsinfo{$lhistfskey}{'package'})
}
```

---

### 3. Enhanced Metadata in FabSite Output

#### Original
- Limited metadata fields in output
- Standard separator usage (vertical tab)

#### Current
- **Added fields:**
  - Family (product family from metadata)
  - Process (process node from metadata)
  - Package (package type from metadata)
- **New timestamp field:**
  - `lim_date`: Extracted date portion only (not full datetime)
  - Selector: `FormatField((split / /, $datetime)[0])`

**Output Column Header Example (BY_PROGRAM):**
```
date_time,Lot_id,fab,Sequence_number,Condition1,Condition2,Condition3,
Step,entity_type,equip_id,product_id,family,process,package,unit_id,site,
parameter_set_id,parameter_set_version,parameter name,exceed_limit,test_flag,
parm_grp_1,parm_grp_2,parm_grp_3,format_flag,result,lim_date,low_lim,high_lim,
recipe,stage,lot class,operator,SOURCE_LOT,LOT_CLASS
```

---

### 4. GetMetaByLot Return Values Enhancement

#### Original
```perl
return ($sourcelot, $lotowner, $lotclass, $productid);
```

#### Current
```perl
if($hOptions{FINALLOT}){
    return ($lot, $hash->{lot_owner}, $hash->{lot_class}, 
            $hash->{product}, $hash->{family}, "N/A", $hash->{package});
}else{
    return ($hash->{source_lot}, $hash->{lot_owner}, $hash->{lot_class}, 
            $hash->{product}, $hash->{family}, $hash->{process}, "N/A");
}
```

**Changes:**
- Returns 7 values instead of 4
- Added family, process, and package information
- Different handling for final lot vs. standard lot
- Supports new product hierarchy information in FabSite output

---

### 5. Lot History Processing Enhancements

#### New Variables in ProcessLhistFile
```perl
my ($sourcelot,$lotowner,$lotclass,$productid,$family,$process,$package) 
    = GetMetaByLot($lotid,$in_productid);
```

#### Storage in lhistfsinfo
```perl
$lhistfsinfo{$key}={"lot_id"=>$lotid,"sourcelot"=>$sourcelot,
    "lotclass"=>$lotclass,"facility"=>$facility,"operation"=>$operation,
    "product_id"=>$productid, "family"=>$family, "process"=>$process, 
    "package"=>$package, # NEW
    "equip_id"=>$equipId,...};
```

**Impact:**
- Enhanced lot history records now include family, process, package
- Enables output flexibility for program-based organization
- Supports advanced metadata enrichment

---

### 6. Parameter Set Test Information Tracking

#### New Feature: addTestInfo() Function
```perl
sub addTestInfo {
    my $parameter_set=shift;
    my $parameter_set_version=shift;
    my $date_stamp=shift;
    my $test_name=shift;
    my $test_units=shift;
    my $test_low_limit=shift;
    my $test_high_limit=shift;
    
    # Builds %parameter_sets hash structure
    # Keys: "parameter_set~~~parameter_set_version"
    # Values: Hash of test definitions with name, units, LSL, HSL
}
```

**New Global Hash:**
```perl
my %parameter_sets=();  # Tracks test information per parameter set version
```

**Usage in ProcessPhistFile:**
```perl
addTestInfo($parasetid, $parasetver, 
            (split / /, $datetime)[0],  # Just the date
            $paraname, $unitid, 
            $lowlimit, $highlimit);
```

**Purpose:**
- Builds test specification database during phist processing
- Enables validation and enrichment of test parameters
- Prepared for downstream YMS (Yield Management System) integration
- Stores "YMS PSET Start Date" for version tracking

---

### 7. Metrology Offline Output Enhancement

#### New Program Name Generation
```perl
my $progName="FSNL::" .  $phistinfo{$holder}{'parameter_set_id'} .
    "::" .  $phistinfo{$holder}{'facility'} . "::WKS";
```

#### New Timestamp Field in Offline Output
```perl
FormatField((split / /, ($phistinfo{$holder}{'date_time'})[0]))
```

**Changes:**
- Added date-only field (previously full datetime)
- Enhanced program naming convention (FSNL = FabSite Non-Lot)
- Improved clarity in offline metrology records

---

### 8. Header Generation Flexibility

#### Original OutputFabSiteLine
- Always included header in output hash

#### Current OutputFabSiteLine
```perl
if ( $pp_method eq "BY_PRODUCT" )
{
    $output{$fname}=$headers{$fname};
    $output{$fname} .= "<DATA>\n";
}
else
{
    $output{$fname} = "<DATA>\n";  # No header for BY_PROGRAM
}
```

**Impact:**
- BY_PROGRAM method omits redundant headers
- BY_PRODUCT method preserves original header behavior
- Reduces output file size for program-based organization
- Error output handles headers independently

---

### 9. PPLogger Integration Enhancement

#### New Parameters in PDF::DpWriter Initialization
```perl
my $wr = PDF::DpWriter->new(
    { ...,
      pplogger => $pplogger  # NEW - passes logger reference
    }
);

$pplogger->setModelHeader($model);  # NEW - sets model header in logger
```

**Enhancements:**
- Improved logging context for LEHS processing
- Better traceability through PPLogger
- Model state tracking for batch operations

---

### 10. Location Configuration

#### Original
- Used `-loc` parameter with hardcoded location codes

#### Current
- Location code converted to uppercase: `$location = uc($hOptions{loc});`
- Facility area parameter now mandatory: `-facilityarea`
- More robust configuration handling

---

## Summary Table

| Aspect | Original | Current |
|--------|----------|---------|
| **Facility Selection** | Boolean flags (-FAB8, -FAB6, etc.) | String parameter (-facilityarea) |
| **Output Organization** | Fixed BY_PRODUCT method | Configurable via -method flag |
| **Metadata Returned** | 4 values | 7 values (added family, process, package) |
| **FabSite Columns** | Standard set | Extended (family, process, package, lim_date) |
| **Parameter Tracking** | Minimal | Enhanced via addTestInfo() |
| **Header Handling** | Always included | Conditional per output method |
| **Metrology Offline** | Basic naming | Enhanced program naming (FSNL prefix) |
| **PPLogger Integration** | Basic | Enhanced with model header tracking |
| **Location Handling** | As-is | Uppercase conversion |

---

## Backward Compatibility Notes

### Breaking Changes
1. **Facility flags removed**: `-FAB8`, `-FAB6`, `-EPI`, `-FINALLOT` replaced with `-facilityarea`
   - **Migration:** Use `-facilityarea FAB8|FAB6|PROBE|EPI` instead
   
2. **GetMetaByLot call sites**: Now expect 7 return values instead of 4
   - **Impact:** Code calling this function must be updated

3. **Command-line interface**: `-facilityarea` is now mandatory
   - **Impact:** All scripts must specify facility area

### Non-Breaking Enhancements
- New `-method BY_PROGRAM` option is optional (defaults to `BY_PRODUCT`)
- New PPLogger parameters in writer initialization
- Enhanced metadata storage is transparent to existing output
- Parameter set tracking is passive (doesn't affect output)

---

## Migration Guide

### For Existing Scripts Using Original Version

**Before (Original):**
```bash
perl fcs_wkstrm_orig.pl -out /data/output -fmtdir /fmt -loc MAINE -fab8 /archive/data.zip
```

**After (Current):**
```bash
perl fcs_wkstrm.pl -out /data/output -fmtdir /fmt -loc MAINE -facilityarea FAB8 /archive/data.zip
```

### For New BY_PROGRAM Output Method

**Example:**
```bash
perl fcs_wkstrm.pl -out /data/output -fmtdir /fmt -loc MAINE \
    -facilityarea FAB8 -method BY_PROGRAM /archive/data.zip
```

**Result:**
- FabSite files grouped by parameter set ID
- Extended metadata columns in output
- Reduced file redundancy for large parameter sets

---

## Implementation Details

### New Global Variables
- `$pp_method` - Output organization method (BY_PRODUCT or BY_PROGRAM)
- `%parameter_sets` - Test specification tracking hash
- `$facilityArea` - Facility area parameter value

### Modified Subroutines
1. `Initialize_argument()` - Added method parsing, facility area validation
2. `OutputFabSiteLine()` - Conditional header/metadata output based on pp_method
3. `GetMetaByLot()` - Extended return values
4. `ProcessLhistFile()` - Stores family/process/package in lhistfsinfo
5. `ProcessPhistFile()` - Calls addTestInfo() for test tracking
6. `OutputMetOffLine()` - Enhanced program naming

### New Subroutines
- `addTestInfo()` - Builds parameter set test information database

---

## Performance Impact

- **Minimal** - Additional metadata handling is lightweight
- **Memory:** Slight increase from `%parameter_sets` tracking
- **Processing:** No significant slowdown from new features
- **Output:** Potentially smaller file size with BY_PROGRAM method due to header consolidation

---

## Testing Recommendations

1. **Backward compatibility test**: Run with `-method BY_PRODUCT` (default)
   - Verify output matches original version
   
2. **New feature test**: Run with `-method BY_PROGRAM`
   - Validate parameter set grouping
   - Check metadata columns are populated
   
3. **Facility area parameter**: Test all facility types
   - FAB8, FAB6, PROBE, EPI
   - Verify case-insensitive matching
   
4. **Metadata enrichment**: Verify family, process, package columns
   - Check values match reference database
   - Validate fallback behavior with missing metadata

---

**Document Version:** 1.0  
**Comparison Date:** 2024-07-14  
**Original Version:** fcs_wkstrm_orig.pl  
**Current Version:** fcs_wkstrm.pl (with enhancements)
