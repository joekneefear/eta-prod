# Lot Attribute File (lot_attr) - Column Structure

## What is a Lot Attribute File?

A **lot_attr file** stores additional information (metadata) about manufacturing lots. Think of it like a **notebook where you write extra details about each lot that aren't in the main files**.

---

## The Five Columns

The lot_attr file has exactly **5 columns** (always in this order):

| Column # | Column Name | What It Means | Example |
|----------|-------------|---------------|---------|
| 1 | **lot_id** | The manufacturing lot identifier | `KG4BNTCX` |
| 2 | **attribute_number** | A code number for the attribute | `2001` |
| 3 | **attribute_name** | What this attribute describes | `SRC LOT 1` |
| 4 | **attribute_type** | Data type: `A` (ASCII text), `N` (numeric), or space (blank) | `A` |
| 5 | **attribute_value** | The actual value of the attribute | `F1300320CNKG49L80R01` |

---

## Breaking Down Your Data

Here's your data with columns labeled:

```
LOT_ID           ATTR_NUM  ATTR_NAME    TYPE  ATTR_VALUE
─────────────────────────────────────────────────────────────
KG4BNTCX         2001      SRC LOT 1    A     F1300320CNKG49L80R01
CENT74020        2001      SRC LOT 1    A     KG4BNRLX
S2E2TCPRS1       2001      SRC LOT 1    A     E0000226CNS2E2TCPRS1
KG48JXJR         2001      SRC LOT 1         (empty/blank)
CENF22618        2001      SRC LOT 1    A     KG4AN1AX
TW72346109S1P7ET 2001      SRC LOT 1         (empty/blank)
S2E2PRSEAO       2002      SRC LOT 2         (empty/blank)
KG417ATR         2002      SRC LOT 2         (empty/blank)
KG4BNTCX         2002      SRC LOT 2         (empty/blank)
S2E2TCPRS1       2002      SRC LOT 2         (empty/blank)
```

---

## File Format (How It's Stored)

The actual format uses **commas to separate columns AND a special marker for the data type**:

```
lot_id,attribute_number,attribute_name,DATA_TYPE_MARKER,attribute_value
```

### The Data Type Marker Rules:

- **`,A,`** = ASCII text (printable characters)
- **`,N,`** = Numeric value (numbers only)
- **`, ,`** = Blank/empty/no data (space character)

---

## Real Examples from Your Data

### Example 1: Normal ASCII Attribute
```
KG4BNTCX,2001,SRC LOT 1,A,F1300320CNKG49L80R01
│        │    │        │ └─ Value: F1300320CNKG49L80R01
│        │    │        └─── Type: ASCII (A)
│        │    └───────────── Attribute Name: SRC LOT 1
│        └────────────────── Attribute Number: 2001
└─────────────────────────── Lot ID: KG4BNTCX
```

**English:** "For lot KG4BNTCX, attribute #2001 (SRC LOT 1) has the text value F1300320CNKG49L80R01"

---

### Example 2: Numeric Attribute (if it existed)
```
KG4BNTCX,3001,WAFER COUNT,N,100
│        │    │           │ └─ Value: 100 (a number)
│        │    │           └─── Type: Numeric (N)
│        │    └─────────────── Attribute Name: WAFER COUNT
│        └──────────────────── Attribute Number: 3001
└───────────────────────────── Lot ID: KG4BNTCX
```

**English:** "For lot KG4BNTCX, attribute #3001 (WAFER COUNT) is the number 100"

---

### Example 3: Blank/Empty Attribute
```
KG48JXJR,2001,SRC LOT 1, ,
│        │    │        │ └─ Value: (nothing - empty)
│        │    │        └─── Type: Blank (space character)
│        │    └───────────── Attribute Name: SRC LOT 1
│        └────────────────── Attribute Number: 2001
└─────────────────────────── Lot ID: KG48JXJR
```

**English:** "For lot KG48JXJR, attribute #2001 (SRC LOT 1) has no value (blank)"

---

## Common Attributes (Examples)

The `attribute_number` and `attribute_name` tell you WHAT information is being stored:

| Attribute # | Typical Name | Meaning | Example Value |
|-------------|--------------|---------|----------------|
| 2001 | SRC LOT 1 | Source lot identifier | F1300320CNKG49L80R01 |
| 2002 | SRC LOT 2 | Another source lot | E0000226CNS2E2TCPRS1 |
| 3001 | WAFER COUNT | Number of wafers | 100 |
| 3002 | DEVICE COUNT | Number of devices | 5000 |
| 4001 | PRODUCTION DATE | When made | 2024-01-15 |
| 5001 | EPI SLOT | Silicon Carbide wafer slot | SiC_SLOT_5 |

---

## How the Script Uses This File

### Step 1: Read the File
The script reads each line of the lot_attr file.

### Step 2: Parse Each Line
Using `getLotAttrColumns()` function, it extracts the 5 columns:
```
Input:  "KG4BNTCX,2001,SRC LOT 1,A,F1300320CNKG49L80R01"
Output: lot=KG4BNTCX
        attr_num=2001
        attr_name=SRC LOT 1
        attr_type=A
        attr_value=F1300320CNKG49L80R01
```

### Step 3: Store the Data
The data is stored in memory for later use:
- Used when creating LATT (Lot Attributes) output files
- Can be used to identify special lots (e.g., SiC lots)
- Included in final output for traceability

### Step 4: Create Output
The script creates `.latt` output file:
- Maximum 100 lots per file (splits into `.1.latt`, `.2.latt`, etc. if needed)
- Tab-separated format (commas replaced with tabs)
- Includes source_lot and lot_class columns added by the script

---

## What Happens with Your Data

Your data shows:

**Lots with attribute #2001 (SRC LOT 1):**
- KG4BNTCX → value: F1300320CNKG49L80R01
- CENT74020 → value: KG4BNRLX
- S2E2TCPRS1 → value: E0000226CNS2E2TCPRS1
- KG48JXJR → (blank)
- CENF22618 → value: KG4AN1AX
- TW72346109S1P7ET → (blank)

**Same lots with attribute #2002 (SRC LOT 2):**
- S2E2PRSEAO → (blank)
- KG417ATR → (blank)
- KG4BNTCX → (blank) [same lot, different attribute]
- S2E2TCPRS1 → (blank) [same lot, different attribute]

**Summary:** Each lot can have multiple attributes, and each attribute can be empty or have a value.

---

## Key Points to Remember

✅ **Always 5 columns:**
1. Lot ID
2. Attribute Number
3. Attribute Name
4. Data Type (A, N, or space)
5. Attribute Value

✅ **Data Type Markers are Important:**
- `A` = Text data (ASCII)
- `N` = Numeric data (numbers)
- Space = No data (blank)

✅ **One Lot Can Have Many Attributes:**
- Same lot can appear multiple times
- Each row = one attribute for that lot

✅ **Same Attribute Number Across Lots:**
- Different lots can share the same attribute number
- E.g., multiple lots all have "SRC LOT 1" (attribute #2001)

✅ **Values Can Be Empty:**
- Some lots don't have values for all attributes
- This is normal and expected

---

## Example: Full Lot Attribute Record

If we followed one lot through the file:

```
Lot: KG4BNTCX

Attribute 1:
  lot_id: KG4BNTCX
  attr_num: 2001
  attr_name: SRC LOT 1
  attr_type: A (text)
  attr_value: F1300320CNKG49L80R01

Attribute 2:
  lot_id: KG4BNTCX
  attr_num: 2002
  attr_name: SRC LOT 2
  attr_type: (blank)
  attr_value: (empty)

Attribute 3:
  lot_id: KG4BNTCX
  attr_num: 3001
  attr_name: WAFER COUNT
  attr_type: N (numeric)
  attr_value: 96
```

**English:** Lot KG4BNTCX has 3 attributes: it came from lot F1300320CNKG49L80R01, has no secondary source lot, and contains 96 wafers.

---

**Document Version:** 1.0  
**For Users:** Beginners  
**Difficulty Level:** Simple
