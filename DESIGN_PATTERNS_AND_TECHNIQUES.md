# Design Patterns and Programming Techniques - INNO FT XLSX Parser Refactoring

## Design Patterns Used

### 1. **Strategy Pattern**
**Purpose:** Encapsulate parsing algorithms and allow runtime selection based on configuration.

**Implementation:**
```python
# Config defines parsing strategy
class InnoFtXlsxSts8200ParserConfig:
    def _create_lot_extractor(self, config: Dict) -> Callable:
        # Returns a strategy function for lot extraction
        def configured_lot_extractor(...):
            # Custom extraction logic
        return configured_lot_extractor

# Parser uses the strategy
parser = InnoFtXlsxSts8200Parser(config=config)
model = parser.parse_to_model(file)
```

**Benefits:**
- Different extraction strategies can be defined in YAML without code changes
- Easy to swap strategies at runtime
- Follows Open/Closed Principle (open for extension, closed for modification)

---

### 2. **Decorator Pattern**
**Purpose:** Add behavior to values through composition of transformations.

**Implementation:**
```python
def _apply_transformations(self, value: str, transforms: Dict) -> str:
    # Stack transformations like decorators
    if transforms.get('trim'):
        value = value.strip()
    if transforms.get('uppercase'):
        value = value.upper()
    if transforms.get('regex'):
        value = re.sub(pattern, replacement, value)
    return value
```

**Benefits:**
- Each transformation is independent and stackable
- New transformations can be added without modifying existing code
- Clean separation of concerns

---

### 3. **Builder Pattern**
**Purpose:** Construct complex configuration objects step by step.

**Implementation:**
```python
# Config builds itself from YAML
config = InnoFtXlsxSts8200ParserConfig(
    config_file='config.yaml',  # Define the blueprint
    site='CUSTOM_SITE'           # Customize for site
)

# Internal building process:
# 1. Load defaults
# 2. Merge global overrides
# 3. Merge site-specific overrides
# 4. Auto-register extractors
```

**Benefits:**
- Complex configuration built progressively
- Defaults + overrides pattern is intuitive
- Configuration state is encapsulated

---

### 4. **Factory Pattern**
**Purpose:** Create extractor functions based on configuration type.

**Implementation:**
```python
class InnoFtXlsxSts8200ParserConfig:
    def _create_lot_extractor(self, config: Dict) -> Callable:
        # Factory for lot extraction strategy
        return configured_lot_extractor
    
    def _create_header_field_extractor(self, config: Dict) -> Callable:
        # Factory for header field extraction strategy
        return configured_header_field_extractor
    
    def _auto_register_extractors(self):
        # Factory registration based on YAML config
        if enabled.get('lot_parser'):
            self.register_extractor('lot_parser', self._create_lot_extractor(...))
```

**Benefits:**
- Encapsulates object creation logic
- Extractors are created based on configuration
- Easy to add new extractor types

---

### 5. **Configuration Object Pattern**
**Purpose:** Centralize all configuration in a single object hierarchy.

**Implementation:**
```python
class InnoFtXlsxSts8200ParserConfig:
    def __init__(self, config_file, site):
        self.config_data = self._get_default_config()  # Defaults
        self._load_yaml_config(config_file, site)      # Load and merge
        self._auto_register_extractors()               # Register strategies
    
    def get_header_labels(self):
    def get_test_header_patterns(self):
    def get_extractor(self, field_name):
    # Single source of truth for all configuration
```

**Benefits:**
- Single Responsibility Principle: Config object handles all configuration
- Dependency Injection: Parser receives config object
- Easy to test (can pass different configs)

---

### 6. **Dependency Injection Pattern**
**Purpose:** Decouple parser from configuration details.

**Implementation:**
```python
# Bad (tight coupling):
class InnoFtXlsxSts8200Parser:
    def __init__(self):
        self.config = yaml.load('hardcoded_file.yaml')  # Tightly coupled

# Good (dependency injection):
class InnoFtXlsxSts8200Parser:
    def __init__(self, config: InnoFtXlsxSts8200ParserConfig = None):
        self.config = config or InnoFtXlsxSts8200ParserConfig()  # Injected
```

**Benefits:**
- Loose coupling between parser and configuration
- Easy to test with mock configs
- Easy to extend with new configurations

---

### 7. **Template Method Pattern**
**Purpose:** Define skeleton of parsing algorithm, let subclasses/config define steps.

**Implementation:**
```python
class InnoFtXlsxSts8200Parser:
    def parse_to_model(self, infile):
        # Template: fixed overall structure
        model = Model(...)
        self._parse_excel_file(infile, model, ...)
        return model
    
    def _parse_excel_file(self, ...):
        # PHASE 1: Find "No" marker
        # PHASE 2: Parse test headers (uses config patterns)
        # PHASE 3: Parse die data
        # Each phase can use configured extractors
```

**Benefits:**
- Algorithm structure is fixed but details are flexible
- Parsing phases are clear and well-defined
- Easy to follow and understand

---

### 8. **Registry Pattern**
**Purpose:** Maintain and access registered extractors dynamically.

**Implementation:**
```python
class InnoFtXlsxSts8200ParserConfig:
    def __init__(self):
        self.custom_extractors = {
            'lot_parser': None,
            'header_field_parser': None,
        }
    
    def register_extractor(self, field_name: str, callback: Callable):
        self.custom_extractors[field_name] = callback
    
    def has_extractor(self, field_name: str) -> bool:
        return self.custom_extractors.get(field_name) is not None
    
    def get_extractor(self, field_name: str) -> Optional[Callable]:
        return self.custom_extractors.get(field_name)
```

**Benefits:**
- Dynamic registration of extraction strategies
- Late binding: extractors registered at runtime
- Allows runtime addition of new extractors

---

## Programming Style Techniques

### 1. **Type Hints (Python 3.12)**
**Usage:** Every function parameter and return type is annotated.

```python
def _apply_transformations(
    self, 
    value: str,                      # Input type
    transforms: Dict[str, Any]       # Complex type
) -> str:                            # Return type
    """Apply transformations..."""
```

**Benefits:**
- Self-documenting code
- IDE autocomplete support
- Static type checking (mypy)
- Catches type errors before runtime

---

### 2. **Docstrings (Google Style)**
**Usage:** Every class and method documented with purpose, args, returns, examples.

```python
def _create_lot_extractor(self, config: Dict[str, Any]) -> Optional[Callable]:
    """
    Create lot ID extractor from YAML configuration.
    
    Supports:
    - Extraction from specific cell/row
    - Regex pattern matching and group extraction
    - Field value parsing/transformation
    
    Args:
        config: Lot ID configuration from YAML
        
    Returns:
        Extractor function or None
    """
```

**Benefits:**
- Clear documentation at point of use
- IDE shows docstrings on hover
- Generated docs (Sphinx) are better quality

---

### 3. **Optional Type with Fallback**
**Usage:** Handle None gracefully with sensible defaults.

```python
def __init__(self, config: Optional[InnoFtXlsxSts8200ParserConfig] = None):
    self.config = config or InnoFtXlsxSts8200ParserConfig()
    # If None passed, create default config
```

**Benefits:**
- Works with or without explicit config
- No null pointer exceptions
- Backward compatible

---

### 4. **Guard Clauses (Early Exit)**
**Usage:** Return early when conditions aren't met, reducing nesting.

```python
# Bad (nested):
if col_a:
    if col_a in self._header_labels:
        if len(row) > 1:
            # Do work
            pass

# Good (guard clauses):
if not col_a:
    continue
if col_a not in self._header_labels:
    continue
if len(row) <= 1:
    continue
# Do work
```

**Benefits:**
- Reduces cognitive load
- Easier to understand conditions
- Avoids deeply nested code

---

### 5. **Composition Over Inheritance**
**Usage:** Config object injected into parser rather than subclassing.

```python
# Composition (used here):
class InnoFtXlsxSts8200Parser:
    def __init__(self, config: InnoFtXlsxSts8200ParserConfig):
        self.config = config  # Compose with config

# vs. Inheritance (avoided):
# class CustomParser(InnoFtXlsxSts8200Parser):
#     def __init__(self):
#         super().__init__()
#         # Override behavior
```

**Benefits:**
- More flexible than inheritance
- Avoids fragile base class problem
- Easy to swap implementations

---

### 6. **Dictionary Over Object for Configuration**
**Usage:** Use Dict[str, Any] for flexible, schema-less configuration.

```python
def _get_default_config(self) -> Dict[str, Any]:
    return {
        'header_labels': {...},
        'field_transformations': {...},
        'test_headers': {...},
    }
```

**Benefits:**
- Flexible: add fields without changing schema
- YAML naturally maps to dicts
- Easy deep merge

---

### 7. **Deep Merge for Configuration Inheritance**
**Usage:** Layer defaults → global → site-specific.

```python
def _load_yaml_config(self, config_file, site):
    base_config = self._get_default_config()      # Start with defaults
    
    if 'defaults' in data:
        self._deep_merge(base_config, data['defaults'])  # Layer 1
    
    if site in data['sites'][site]:
        self._deep_merge(base_config, data['sites'][site])  # Layer 2
```

**Benefits:**
- Hierarchical configuration
- Override only what you need to change
- Clear precedence: defaults < global < site-specific

---

### 8. **Lazy Compilation of Regex Patterns**
**Usage:** Compile regex patterns once at initialization, not repeatedly.

```python
def _compile_test_patterns(self) -> Dict[str, re.Pattern]:
    """Compile patterns once at init time"""
    compiled = {}
    for config_key, pattern_str in config_patterns.items():
        compiled[pattern_key] = re.compile(pattern_str, re.IGNORECASE)
    return compiled
    
def _parse_excel_file(self, ...):
    # Reuse compiled patterns (no recompilation)
    if col_a and self._test_patterns['test_num_row'].match(col_a):
```

**Benefits:**
- Performance: regex compiled once, not per-row
- Cleaner code: reuse pattern objects
- Cache warm: patterns ready for parsing

---

### 9. **Context Management (Implicit)**
**Usage:** Resource cleanup via context managers where applicable.

```python
workbook = load_workbook(infile, data_only=True, read_only=True)
worksheet = workbook.worksheets[0]
# openpyxl handles cleanup automatically
# (Explicit cleanup not needed for read-only mode)
```

**Benefits:**
- Resources properly managed
- File handles released
- Memory efficiently used

---

### 10. **Constants and Lookup Tables**
**Usage:** Use dictionaries for pattern lookup instead of if/elif chains.

```python
# Good (lookup table):
_PATTERNS = {
    'numeric_row': re.compile(r'^\d+$'),
    'test_param': re.compile(r'Test\s*Parameter', re.IGNORECASE),
    'll_limit': re.compile(r'^LL$', re.IGNORECASE),
}

if col_a and self._PATTERNS['test_num_row'].match(col_a):
    # Do work

# vs. Bad (if/elif chain):
# if col_a and test_num_pattern.match(col_a):
# elif col_a and test_param_pattern.match(col_a):
# elif col_a and ll_limit_pattern.match(col_a):
```

**Benefits:**
- More maintainable
- Easier to add new patterns
- Uniform lookup behavior

---

### 11. **Logging Levels for Traceability**
**Usage:** Strategic logging at different verbosity levels.

```python
Log.INFO("Starting parser configuration...")           # High-level flow
Log.DEBUG(f"Attempting to match LotID '{lot_upper}'")  # Detailed debugging
Log.WARN("Site not found in config, using defaults")   # Warnings
Log.ERROR("Failed to parse XLSX: {e}")                 # Errors
```

**Benefits:**
- Traceability of execution flow
- Debug mode shows detailed info
- Production logs show only important events

---

### 12. **Error Handling with Fallback**
**Usage:** Try-catch with sensible fallback behavior.

```python
try:
    pattern = re.compile(pattern_str)
except re.error as e:
    Log.ERROR(f"Invalid regex: {e}")
    compiled[pattern_name] = self._PATTERNS.get(pattern_name, re.compile(''))
    # Fallback to default pattern
```

**Benefits:**
- Graceful degradation
- Application continues despite errors
- Clear error messages for debugging

---

### 13. **Private Methods with Underscore Prefix**
**Usage:** Methods prefixed with `_` indicate internal implementation.

```python
def _load_yaml_config(self, config_file, site):  # Private
    """Internal method"""

def _deep_merge(self, target, source):           # Private
    """Internal utility"""

def get_header_labels(self):                      # Public API
    """Public interface"""
```

**Benefits:**
- Clear public vs. private interface
- Signals what users should call
- Prevents accidental misuse

---

### 14. **Defensive Programming**
**Usage:** Check conditions before use; validate inputs.

```python
if config_file and isinstance(config_file, str) and os.path.exists(config_file):
    # Check: not None, is string, file exists
    self._load_yaml_config(config_file, site)

if site and 'sites' in data and site in data['sites']:
    # Check: site provided, key exists, site in dict
    site_config = data['sites'][site]
```

**Benefits:**
- Prevents runtime errors
- Clear assumptions about data
- Robust code that handles edge cases

---

### 15. **F-Strings for String Interpolation**
**Usage:** Modern Python string formatting.

```python
# Good (f-string):
Log.INFO(f"Loaded config for site: {site} (merged with defaults)")

# vs. Old (str.format):
# Log.INFO("Loaded config for site: {} (merged with defaults)".format(site))

# vs. Very old (% formatting):
# Log.INFO("Loaded config for site: %s (merged with defaults)" % site)
```

**Benefits:**
- More readable
- Cleaner syntax
- Better performance

---

### 16. **Comprehensions for Transformations**
**Usage:** List/dict comprehensions for concise data transformation.

```python
# Compile patterns from config
compiled = {
    pattern_name: re.compile(pattern_str, re.IGNORECASE)
    for pattern_name, pattern_str in patterns.items()
    if pattern_str
}

# Extract cell values
test_names = [self._clean_cell(c) for c in row[2:]]
```

**Benefits:**
- Concise and Pythonic
- More readable than loops
- Better performance

---

### 17. **Generator Expressions for Memory Efficiency**
**Usage:** Lazy evaluation where appropriate.

```python
# Efficient for large files:
all_rows = list(worksheet.iter_rows(values_only=True))
# Converts to list once; then indexed many times

# vs. Without list():
# for row in worksheet.iter_rows(values_only=True):
#     # Would iterate row-by-row (less suitable for 3-phase parsing)
```

**Benefits:**
- Memory efficient for large datasets
- Fast indexed access for multiple passes
- Clear data ownership

---

## Programming Principles Applied

### SOLID Principles

| Principle | Implementation |
|-----------|-----------------|
| **S**ingle Responsibility | Config class handles configuration; Parser handles parsing |
| **O**pen/Closed | New extractors via configuration, not code modification |
| **L**iskov Substitution | Extractors are interchangeable functions |
| **I**nterface Segregation | Small, focused interfaces (get_header_labels, get_extractor) |
| **D**ependency Inversion | Parser depends on Config abstraction, not concrete YAML |

### DRY (Don't Repeat Yourself)
- `_apply_transformations()` handles all value transformations (used by multiple extractors)
- `_compile_test_patterns()` centralized pattern compilation
- Configuration defaults prevent duplication

### YAGNI (You Aren't Gonna Need It)
- Only implements extractors and transformations that are actually used
- No over-engineering or speculative features
- Configuration is flexible but focused

### Keep It Simple, Stupid (KISS)
- Clear three-phase parsing approach
- Straightforward configuration hierarchy
- No unnecessary complexity

---

## Scalability Considerations

### Horizontal Scalability
```python
# Multiple sites can have different configs
parser_configs = {
    'SITE_A': InnoFtXlsxSts8200ParserConfig('config.yaml', 'SITE_A'),
    'SITE_B': InnoFtXlsxSts8200ParserConfig('config.yaml', 'SITE_B'),
}

# Each parser is independent
parsers = {site: InnoFtXlsxSts8200Parser(config=config) 
           for site, config in parser_configs.items()}
```

### Adding New Extractors
```yaml
sites:
  NEW_SITE:
    custom_parsers:
      lot_parser: true        # Enable custom lot extraction
    
    lot_id:
      source: 'header_field'
      field_label: 'CustomLotField'
      pattern: '^CUSTOM-(\w+)-\d+$'
      groups:
        1: 'LOT'
      transformations:
        uppercase: true
```

### Adding New Transformations
```python
# Just add to _apply_transformations() method
if transforms.get('custom_flag'):
    # Apply custom transformation
    value = custom_transform(value)

# Or define in YAML and the logic is centralized
```

---

## Conclusion

This solution demonstrates **enterprise-grade Python architecture** by combining multiple design patterns and best practices to create a:

1. **Maintainable:** Clear separation of concerns, well-documented code
2. **Extensible:** New features via configuration, not code modification
3. **Testable:** Dependencies injected, easy to mock configurations
4. **Scalable:** Support for multiple sites and extractors
5. **Robust:** Error handling, defensive programming, logging
6. **Professional:** Type hints, docstrings, consistent style

The architecture balances flexibility with simplicity, making it suitable for production use while remaining accessible for future developers.
