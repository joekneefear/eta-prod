# Scribe & Wafer Number Data Extraction Guide

## Quick Answer

**YES**, the scripts CAN extract scribe and wafer information, but **ONLY if it's in the source data files**. The scripts don't generate or calculate this information—they just pass through what's already there.

---

## What Data CAN Be Extracted

### 1. Unit ID (Scribe/Wafer Identifier)
**Source:** Parameter History File (phist)  
**Column Name:** `unit_id`  
**What it is:** A wafer/scribe identifier for each test site

**How it appears in output:**
- **FabSite (FS)** output: `unit_id` column
- **Offline Metrology (OFF)** output: `unit_id` column

**Example:**
```
Parameter History input:  unit_id = "LEFT" or "CENTER" or "RIGHT" or "123" or empty
FabSite output:           unit_id = "LEFT" (or whatever was in the input)
```

---

### 2. Site Number
**Source:** Parameter History File (phist)  
**Column Name:** `site` (calculated by script)  
**What it is:** A sequential site number (1, 2, 3, etc.) that increments for each parameter value

**How it's calculated:**
- Script starts at site 1
- For each parameter value in the test, it increments: 1, 2, 3, 4, 5...
- Resets for each lot/equipment/test combination

**How it appears in output:**
- **FabSite (FS)** output: `site` column
- **Offline Metrology (OFF)** output: `site` column

**Example:**
```
If a test has 5 parameter values:
  site 1 → first parameter value
  site 2 → second parameter value
  site 3 → third parameter value
  site 4 → fourth parameter value
  site 5 → fifth parameter value
```

---

### 3. Unit Change (Lot Quantity Changes)
**Source:** Lot History File (lhist)  
**Column Name:** `unit_change`  
**What it is:** The change in quantity (how many units were added/removed)

**How it appears in output:**
- **LOTEVENT (Lot Event)** output: `unit_change` column

**Example:**
```
Lot started with 100 wafers
After processing: 98 wafers
unit_change = -2 (2 wafers were lost/scrapped)
```

---

### 4. EPI SLOT Attribute (Silicon Carbide Tracking)
**Source:** Lot Attribute File (lot_attr)  
**Attribute Name:** `EPI SLOT`  
**What it is:** Special identifier for Silicon Carbide (SiC) wafers

**How it's used:**
- Script identifies "EPI SLOT" attributes
- Stores them in `%sicinfo` hash for SiC lot tracking
- Used internally but doesn't appear in standard output

**Example from lot_attr:**
```
Input:  KG4BNTCX,5001,EPI SLOT,A,SiC_SLOT_5
Script: Recognizes this as SiC lot tracking
Storage: %sicinfo{KG4BNTCX}{"EPI SLOT"} = "SiC_SLOT_5"
```

---

## Where This Data COMES FROM (Input Files)

### Parameter History File (phist)
This is where most scribe/wafer data originates.

**Columns that relate to scribe/wafer:**
```
parameter_set_id      → Test name/ID
parameter_set_version → Test version
parameter_name        → Specific test name
unit_id               → ← WAFER/SCRIBE ID (THIS IS WHAT YOU WANT!)
sequence_number       → Order of measurement
number_of_values      → How many measurements in this test
c_value_1 to c_value_5 → Text measurement values
d_value_1 to d_value_5 → Numeric measurement values
date_time             → When test was run
facility              → Which fab/location
type_id               → Equipment ID
```

**Example Parameter History line:**
```
WB-CSPL-L,REV1,RESISTANCE,LEFT,1,5,0.005,0.006,0.007,0.008,0.009,,,,2024-01-15 10:30:25,MAINE,PROBE01
                              ↑
                              unit_id = "LEFT" (this is the wafer/scribe position)
```

### Lot Attribute File (lot_attr)
Can store additional scribe/wafer information via custom attributes.

**Example:**
```
lot_id,attribute_number,attribute_name,attribute_type,attribute_value
KG4BNTCX,2001,SRC LOT 1,A,F1300320CNKG49L80R01
KG4BNTCX,5001,EPI SLOT,A,SiC_SLOT_5
          ↑                    ↑
          Custom attribute    Scribe/wafer info if stored here
```

---

## What Data CANNOT Be Extracted

### ❌ NOT Available:
- **Die coordinates** (X,Y position on wafer) - Not in these source files
- **Wafer map data** - Not captured by this script
- **Physical defects** - Not in the data format
- **Yield information by site** - Not extracted
- **Cross-die correlations** - Not calculated

### Why NOT?
These scripts are designed for **manufacturing process tracking**, not **detailed defect/yield analysis**. They focus on:
- Lot movement through operations
- Test results and pass/fail data
- Equipment history
- Loss/scrap tracking

---

## How Scripts Handle Unit_ID

### Step 1: Read from Parameter History
```perl
if ($work[$i] eq "unit_id")
{
    $unitidColumn = $i;  # Mark column location
}

# Later, when processing data:
my $unitid = $work[$unitidColumn];  # Extract unit_id value
$unitid =~ s/'//g;  # Remove single quotes if present
```

### Step 2: Clean Up Value
```perl
if($unitid =~ /^\s*$/){
    DEBUG("optional unitid undefined");
    # It's okay if empty
}
```

### Step 3: Pass to Output
```perl
# In FabSite output:
."\cK".FormatField($unitid)  # Add unit_id to output line

# In Offline Metrology:
,FormatField($unitid)        # Add unit_id to pipe-delimited output
```

---

## Real Example: Data Flow

### Input (Parameter History File)
```
parameter_set_id,parameter_set_version,parameter_name,unit_id,sequence_number,c_value_1,...
WB-CSPL-L,REV1,RESISTANCE,LEFT,1,0.005,...
WB-CSPL-L,REV1,RESISTANCE,CENTER,2,0.006,...
WB-CSPL-L,REV1,RESISTANCE,RIGHT,3,0.007,...
```

### Processing
```
Script reads each line:
1. unit_id = "LEFT"   → sequence_number = 1 → site = 1
2. unit_id = "CENTER" → sequence_number = 2 → site = 2
3. unit_id = "RIGHT"  → sequence_number = 3 → site = 3
```

### Output (FabSite - FS file)
```
date_time|lot_id|fab|sequence_number|...|unit_id|site|...
2024-01-15 10:30:25|KG4BNTCX|MAINE|1|...|LEFT|1|...
2024-01-15 10:30:25|KG4BNTCX|MAINE|2|...|CENTER|2|...
2024-01-15 10:30:25|KG4BNTCX|MAINE|3|...|RIGHT|3|...
```

---

## Output File Columns with Wafer/Scribe Data

### FabSite (FS) Output
**Columns related to scribe/wafer:**
```
unit_id        → Wafer/scribe identifier (from input)
site           → Sequential site number (1, 2, 3...)
Lot_id         → Which lot
parameter_set_id → Which test
parameter_name   → Test name
result         → Test result value
```

**Example FS output line:**
```
2024-01-15 10:30:25|KG4BNTCX|MAINE|1|LEH_WKS|OPERATION_010|0|Equipment_01|WB-CSPL-L|REV1|RESISTANCE|0|0|FAIL|TEST_GRP_1|TEST_GRP_2|TEST_GRP_3|TEXT|0.0052|2024-01-01|0.005|0.010|Recipe_v1|STAGE_01|source_lot_1|operator_1|LEFT|1|TEST_INFO
                                                                                                                                                                                                                                                    ↑   ↑
                                                                                                                                                                                                                                              unit_id site
```

### Offline Metrology (OFF) Output
**Columns related to scribe/wafer:**
```
unit_id              → Wafer/scribe identifier
site                 → Sequential site number
parameter_set_id     → Test identifier
parameter_name       → Test name
result               → Measurement value
```

**Example OFF output line:**
```
2024-01-15 10:30:25|MAINE|Equipment_Probe|PROBE01|123|LEFT|1|WB-CSPL-L|REV1|RESISTANCE|1|0|TEST_GRP|0.0052|2024-01-01|0.005|0.010
                                                                      ↑     ↑
                                                                   unit_id site
```

### LOTEVENT Output
**Columns related to quantity changes:**
```
unit_change          → Change in lot quantity
lot_quantity_new     → New quantity after change
```

**Example:**
```
lot_id|facility|transaction|transaction_date_time|operation|...|unit_change|lot_quantity_new|...
KG4BNTCX|MAINE|MVOU|2024-01-15 10:30:25|OPERATION_010|...|-2|98|...
                                                           ↑  ↑
                                                    unit_change lost 2 units
```

---

## Common Unit_ID Values

These are typical values found in the unit_id field:

| Value | Meaning |
|-------|---------|
| `LEFT` | Left position on multi-position test |
| `CENTER` | Center position |
| `RIGHT` | Right position |
| `TOP` | Top position |
| `BOTTOM` | Bottom position |
| `1`, `2`, `3`... | Numeric site identifiers |
| Empty | No specific position (single site test) |
| `SiC_SLOT_1`... | Silicon Carbide wafer slot |
| Custom text | Equipment-specific identifier |

---

## How to Check if Your Data Has Scribe/Wafer Info

### Step 1: Look at Format File
Check the `.bcp_fmt` file for parameter history:
```bash
grep "unit_id" parameter_history.bcp_fmt
```

If found: ✅ Your source file has unit_id column

If not found: ❌ Your source file doesn't have unit_id data

### Step 2: Check Parameter History File
Open the actual phist/parameter_history file and look for a column labeled `unit_id`

**If you see it:**
```
parameter_set_id,parameter_set_version,parameter_name,unit_id,c_value_1,...
WB-CSPL-L,REV1,RESISTANCE,LEFT,0.005,...
                           ↑
                    Found unit_id data!
```

**If you don't see it:**
```
parameter_set_id,parameter_set_version,parameter_name,c_value_1,...
WB-CSPL-L,REV1,RESISTANCE,0.005,...
                          ↑
                   No unit_id column
```

### Step 3: Check Output Files
Look at generated FS or OFF output:
```bash
grep "LEFT\|CENTER\|RIGHT" output_fs_*.iff
```

If found: ✅ Scribe/wafer data was extracted and included

---

## Limitations and Gotchas

### ⚠️ Important:
1. **Script passes through data as-is** - It doesn't validate that unit_id values make sense
2. **Empty unit_id is okay** - Script treats empty unit_id as valid (single-site test)
3. **No site consolidation** - Script just increments site number; doesn't correlate with unit_id
4. **No physical mapping** - Script doesn't know or care about actual wafer positions
5. **No correlation with yield** - Unit_id is just a label; no pass/fail analysis by site

### 📝 Example of Gotcha:
```
Input:  unit_id = "LEFT" for test 1
        unit_id = "LEFT" for test 2
        
Output: site = 1 for test 1  (LEFT = site 1)
        site = 1 for test 2  (LEFT = site 1 again)
        
Result: Same unit_id, but different tests, same site number
        This is CORRECT - site numbers restart per test
```

---

## Summary

| Question | Answer |
|----------|--------|
| Can scripts extract scribe/wafer info? | **YES** - If it's in source files |
| Where from? | **Parameter History (phist) file** |
| What column? | **`unit_id`** |
| Where does it appear? | **FS and OFF output files** |
| Is it calculated? | **No** - Just passed through from input |
| Can I get detailed site analysis? | **No** - Not designed for that |
| What if unit_id is empty? | **OK** - Script handles it fine |

---

## Files Involved

### Input Files
- `parameter_history.bcp_fmt` - Format definition (tells script what columns exist)
- `phist` / `parameter_history` - Actual data file with unit_id column
- `lot_attr` - Optional: Can store additional wafer/scribe attributes

### Output Files
- `FS` (FabSite) - Contains unit_id and site columns
- `OFF` (Offline Metrology) - Contains unit_id and site columns  
- `LATT` (Lot Attributes) - Contains custom attributes (e.g., EPI SLOT)

---

## Next Steps

To use this data:

1. **Verify your source file has unit_id column** - Check format definition
2. **Run the script** - It will automatically extract and include unit_id data
3. **Check output files** - Look for unit_id column in FS and OFF outputs
4. **Use output for** - Test result analysis, equipment tracking, wafer position mapping

---

**Document Version:** 1.0  
**For Users:** Intermediate  
**Difficulty:** Moderate
