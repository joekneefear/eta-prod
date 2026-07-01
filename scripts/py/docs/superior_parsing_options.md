# Superior Custom Parsing Options - Analysis & Recommendations

## Current Approach Review

### Current Implementation (Callback-Based)

```python
# In main script
config = ParserConfig()
config.register_extractor('lot_parser', LotIdExtractor.extract)
config.register_extractor('program_parser', TestProgramExtractor.extract)

parser = Dts1000XlsParser(config)
model = parser.parse_to_model(infile)
```

**Pros**:
- ✅ Simple and straightforward
- ✅ Flexible - can register any function
- ✅ No file dependencies

**Cons**:
- ❌ Requires code changes for new extractors
- ❌ Not data-driven
- ❌ Command-line flags needed for each extractor
- ❌ Hard to maintain multiple configurations

---

## Superior Option 1: YAML Configuration File ⭐⭐⭐⭐⭐

### Concept

**Store custom parsing rules in a YAML file** that can be modified without code changes.

### Implementation

#### 1. Configuration File: `dts1000_custom_parsers.yaml`

```yaml
# DTS1000 Custom Parser Configuration

# Site-specific configurations
sites:
  PHXFT:
    # Enable/disable custom parsers
    custom_parsers:
      lot_parser: true
      program_parser: true
      time_parser: true
    
    # Lot ID parsing rules
    lot_id:
      pattern: '^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
      groups:
        1: PROCESS
        2: PRODUCT
        3: INTERNAL_CONTROL
        4: LOT
      fallback: 'LOT'  # Field to use if pattern doesn't match
    
    # Program parsing rules
    program:
      extract_revision: true
      revision_position: -1  # Last character
      strip_extension: true
    
    # Timestamp rules
    timestamp:
      source: 'file_modified'  # or 'excel_date' or 'current'
      format: '%Y/%m/%d %H:%M:%S'
  
  SITE2:
    custom_parsers:
      lot_parser: false  # Use default parsing
      program_parser: true
      time_parser: false
    
    program:
      extract_revision: false

# Global defaults
defaults:
  lot_id:
    pattern: null  # No pattern matching
  program:
    extract_revision: false
  timestamp:
    source: 'excel_date'
```

#### 2. Enhanced ParserConfig Class

```python
class ParserConfig:
    """Configuration with YAML file support."""
    
    def __init__(self, config_file: Optional[str] = None, site: Optional[str] = None):
        """
        Initialize with optional YAML configuration.
        
        Args:
            config_file: Path to YAML configuration file
            site: Site name for site-specific config
        """
        self.custom_extractors = {
            'lot_parser': None,
            'program_parser': None,
            'time_parser': None,
        }
        
        self.config_data = {}
        
        if config_file and os.path.exists(config_file):
            self._load_yaml_config(config_file, site)
    
    def _load_yaml_config(self, config_file: str, site: Optional[str]):
        """Load configuration from YAML file."""
        import yaml
        
        with open(config_file, 'r') as f:
            data = yaml.safe_load(f)
        
        # Get site-specific or default config
        if site and site in data.get('sites', {}):
            self.config_data = data['sites'][site]
        else:
            self.config_data = data.get('defaults', {})
        
        # Auto-register extractors based on config
        self._auto_register_extractors()
    
    def _auto_register_extractors(self):
        """Automatically register extractors based on YAML config."""
        from lib.Parser.CustomExtractors import (
            LotIdExtractor,
            TestProgramExtractor,
            DataportTimeExtractor
        )
        
        enabled = self.config_data.get('custom_parsers', {})
        
        if enabled.get('lot_parser'):
            # Create configured lot extractor
            lot_config = self.config_data.get('lot_id', {})
            extractor = LotIdExtractor.create_from_config(lot_config)
            self.register_extractor('lot_parser', extractor)
        
        if enabled.get('program_parser'):
            program_config = self.config_data.get('program', {})
            extractor = TestProgramExtractor.create_from_config(program_config)
            self.register_extractor('program_parser', extractor)
        
        if enabled.get('time_parser'):
            timestamp_config = self.config_data.get('timestamp', {})
            extractor = DataportTimeExtractor.create_from_config(timestamp_config)
            self.register_extractor('time_parser', extractor)
```

#### 3. Enhanced Extractors with Config Support

```python
class LotIdExtractor(CustomExtractor):
    """Extract lot components with configurable pattern."""
    
    @staticmethod
    def create_from_config(config: Dict[str, Any]):
        """Create extractor from YAML config."""
        pattern = config.get('pattern')
        groups = config.get('groups', {})
        fallback = config.get('fallback', 'LOT')
        
        def configured_extractor(raw_data, context):
            lot_string = raw_data.get('LotName', '')
            
            if pattern:
                match = re.match(pattern, lot_string)
                if match:
                    result = {}
                    for group_num, field_name in groups.items():
                        result[field_name] = match.group(int(group_num))
                    return result
            
            # Fallback
            return {fallback: lot_string}
        
        return configured_extractor
```

#### 4. Usage in Main Script

```python
def main():
    # ... argument processing ...
    
    site = params['site']
    config_file = params.get('parser_config', 
                             '/export/home/dpower/project/scripts/py/resources/dts1000_custom_parsers.yaml')
    
    # Create parser with YAML configuration
    parser_config = ParserConfig(config_file=config_file, site=site)
    parser = Dts1000XlsParser(config=parser_config)
    
    # That's it! No manual extractor registration needed
    model = parser.parse_to_model(output)
```

### Advantages

- ✅ **Zero code changes** for new sites
- ✅ **Data-driven** configuration
- ✅ **Easy to maintain** - just edit YAML
- ✅ **Site-specific** rules
- ✅ **Version controlled** configuration
- ✅ **No command-line flags** needed
- ✅ **Self-documenting** with YAML comments

---

## Superior Option 2: Plugin Architecture ⭐⭐⭐⭐

### Concept

**Load custom extractors as plugins** from a directory.

### Implementation

#### 1. Plugin Directory Structure

```
scripts/py/lib/Parser/plugins/
├── __init__.py
├── phxft_lot_parser.py
├── phxft_program_parser.py
├── site2_lot_parser.py
└── generic_time_parser.py
```

#### 2. Plugin Base Class

```python
# lib/Parser/PluginBase.py

from abc import ABC, abstractmethod
from typing import Dict, Any

class ParserPlugin(ABC):
    """Base class for parser plugins."""
    
    # Plugin metadata
    name: str = "base_plugin"
    version: str = "1.0"
    site: str = "ALL"  # or specific site
    field: str = "unknown"  # lot_parser, program_parser, etc.
    
    @abstractmethod
    def extract(self, raw_data: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
        """Extract fields from raw data."""
        pass
    
    @classmethod
    def is_applicable(cls, site: str, field: str) -> bool:
        """Check if plugin applies to site and field."""
        return (cls.site == "ALL" or cls.site == site) and cls.field == field
```

#### 3. Example Plugin

```python
# lib/Parser/plugins/phxft_lot_parser.py

from lib.Parser.PluginBase import ParserPlugin
import re

class PhxftLotParser(ParserPlugin):
    """PHXFT-specific lot ID parser."""
    
    name = "phxft_lot_parser"
    version = "1.0"
    site = "PHXFT"
    field = "lot_parser"
    
    def extract(self, raw_data, context):
        lot_string = raw_data.get('LotName', '')
        
        # PHXFT pattern: PROCESS-DEVICE-CONTROL-LOT
        pattern = r'^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
        match = re.match(pattern, lot_string)
        
        if match:
            return {
                'PROCESS': match.group(1),
                'PRODUCT': match.group(2),
                'INTERNAL_CONTROL': match.group(3),
                'LOT': match.group(4),
            }
        
        return {'LOT': lot_string}
```

#### 4. Plugin Loader

```python
# lib/Parser/PluginLoader.py

import os
import importlib
import inspect
from typing import List, Type
from lib.Parser.PluginBase import ParserPlugin

class PluginLoader:
    """Load and manage parser plugins."""
    
    def __init__(self, plugin_dir: str = None):
        if plugin_dir is None:
            plugin_dir = os.path.join(os.path.dirname(__file__), 'plugins')
        
        self.plugin_dir = plugin_dir
        self.plugins: List[Type[ParserPlugin]] = []
        self._load_plugins()
    
    def _load_plugins(self):
        """Discover and load all plugins."""
        if not os.path.exists(self.plugin_dir):
            return
        
        for filename in os.listdir(self.plugin_dir):
            if filename.endswith('.py') and not filename.startswith('__'):
                module_name = filename[:-3]
                self._load_plugin_module(module_name)
    
    def _load_plugin_module(self, module_name: str):
        """Load a single plugin module."""
        try:
            module = importlib.import_module(f'lib.Parser.plugins.{module_name}')
            
            for name, obj in inspect.getmembers(module):
                if (inspect.isclass(obj) and 
                    issubclass(obj, ParserPlugin) and 
                    obj != ParserPlugin):
                    self.plugins.append(obj)
        except Exception as e:
            Log.WARN(f"Failed to load plugin {module_name}: {e}")
    
    def get_plugin(self, site: str, field: str) -> Optional[ParserPlugin]:
        """Get applicable plugin for site and field."""
        for plugin_class in self.plugins:
            if plugin_class.is_applicable(site, field):
                return plugin_class()
        return None
```

#### 5. Usage

```python
# In ParserConfig
class ParserConfig:
    def __init__(self, site: str = None, use_plugins: bool = True):
        self.custom_extractors = {}
        
        if use_plugins and site:
            self._load_plugins(site)
    
    def _load_plugins(self, site: str):
        """Load plugins for site."""
        loader = PluginLoader()
        
        for field in ['lot_parser', 'program_parser', 'time_parser']:
            plugin = loader.get_plugin(site, field)
            if plugin:
                self.register_extractor(field, plugin.extract)
                Log.INFO(f"Loaded plugin: {plugin.name} v{plugin.version}")
```

### Advantages

- ✅ **Hot-swappable** - add plugins without restart
- ✅ **Modular** - each site can have own plugins
- ✅ **Version controlled** - plugins are code
- ✅ **Testable** - each plugin can be unit tested
- ✅ **Discoverable** - auto-loads from directory
- ✅ **Isolated** - plugin failures don't break parser

---

## Superior Option 3: Inheritance-Based Approach ⭐⭐⭐

### Concept

**Create site-specific parser subclasses** that override parsing methods.

### Implementation

```python
# lib/Parser/Dts1000PhxftParser.py

from lib.Parser.Dts1000XlsParser import Dts1000XlsParser
import re

class Dts1000PhxftParser(Dts1000XlsParser):
    """PHXFT-specific DTS1000 parser with custom field extraction."""
    
    def _parse_lot_field(self, row_data, header, context):
        """Override lot parsing for PHXFT pattern."""
        if len(row_data) > 2:
            lot_string = Util.trim(row_data[2])
            
            # PHXFT pattern
            pattern = r'^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
            match = re.match(pattern, lot_string)
            
            if match:
                header.PROCESS = match.group(1)
                header.PRODUCT = match.group(2)
                header.INTERNAL_CONTROL = match.group(3)
                header.LOT = match.group(4)
            else:
                header.LOT = lot_string
    
    def _parse_program_field(self, row_data, header, context):
        """Override program parsing for PHXFT."""
        if len(row_data) > 2:
            test_filename = row_data[2]
            basename = os.path.basename(test_filename)
            basename = os.path.splitext(basename)[0]
            
            if len(basename) > 1:
                header.PROGRAM = basename[:-1]
                header.REVISION = basename[-1]
            else:
                header.PROGRAM = basename
```

#### Usage

```python
# In main script
def get_parser_for_site(site: str):
    """Factory function to get site-specific parser."""
    parsers = {
        'PHXFT': Dts1000PhxftParser,
        'SITE2': Dts1000Site2Parser,
        # ... more sites
    }
    
    parser_class = parsers.get(site, Dts1000XlsParser)
    return parser_class()

# Usage
parser = get_parser_for_site(site)
model = parser.parse_to_model(output)
```

### Advantages

- ✅ **Type-safe** - IDE autocomplete works
- ✅ **Clear inheritance** - easy to understand
- ✅ **No configuration files** needed
- ✅ **Full control** - can override any method

### Disadvantages

- ❌ Requires new class for each site
- ❌ More code duplication
- ❌ Less flexible than config-based

---

## Superior Option 4: Decorator Pattern ⭐⭐⭐⭐

### Concept

**Use decorators to register extractors** with metadata.

### Implementation

```python
# lib/Parser/ExtractorRegistry.py

class ExtractorRegistry:
    """Global registry for custom extractors."""
    
    _extractors = {}
    
    @classmethod
    def register(cls, field: str, site: str = "ALL", priority: int = 0):
        """Decorator to register an extractor."""
        def decorator(func):
            key = f"{site}:{field}"
            if key not in cls._extractors:
                cls._extractors[key] = []
            
            cls._extractors[key].append({
                'func': func,
                'priority': priority,
                'site': site,
                'field': field
            })
            
            # Sort by priority (higher first)
            cls._extractors[key].sort(key=lambda x: x['priority'], reverse=True)
            
            return func
        return decorator
    
    @classmethod
    def get_extractor(cls, field: str, site: str):
        """Get best matching extractor."""
        # Try site-specific first
        key = f"{site}:{field}"
        if key in cls._extractors and cls._extractors[key]:
            return cls._extractors[key][0]['func']
        
        # Try global
        key = f"ALL:{field}"
        if key in cls._extractors and cls._extractors[key]:
            return cls._extractors[key][0]['func']
        
        return None
```

#### Define Extractors with Decorators

```python
# lib/Parser/SiteExtractors.py

from lib.Parser.ExtractorRegistry import ExtractorRegistry

@ExtractorRegistry.register('lot_parser', site='PHXFT', priority=10)
def phxft_lot_extractor(raw_data, context):
    """PHXFT lot ID extractor."""
    lot_string = raw_data.get('LotName', '')
    pattern = r'^([A-Z]+)-([A-Z0-9]+)-([A-Z0-9]+)-([A-Z0-9]+)$'
    match = re.match(pattern, lot_string)
    
    if match:
        return {
            'PROCESS': match.group(1),
            'PRODUCT': match.group(2),
            'INTERNAL_CONTROL': match.group(3),
            'LOT': match.group(4),
        }
    return {'LOT': lot_string}

@ExtractorRegistry.register('program_parser', site='PHXFT', priority=10)
def phxft_program_extractor(raw_data, context):
    """PHXFT program extractor."""
    # ... implementation

@ExtractorRegistry.register('lot_parser', site='ALL', priority=0)
def default_lot_extractor(raw_data, context):
    """Default lot extractor (fallback)."""
    return {'LOT': raw_data.get('LotName', '')}
```

#### Usage

```python
# In ParserConfig
class ParserConfig:
    def __init__(self, site: str = None):
        self.custom_extractors = {}
        
        if site:
            self._load_from_registry(site)
    
    def _load_from_registry(self, site: str):
        """Load extractors from global registry."""
        for field in ['lot_parser', 'program_parser', 'time_parser']:
            extractor = ExtractorRegistry.get_extractor(field, site)
            if extractor:
                self.register_extractor(field, extractor)
```

### Advantages

- ✅ **Clean syntax** - decorators are elegant
- ✅ **Priority system** - multiple extractors can coexist
- ✅ **Auto-discovery** - just import the module
- ✅ **Flexible** - can register at runtime
- ✅ **Testable** - each extractor is a function

---

## Recommendation Matrix

| Approach | Ease of Use | Flexibility | Maintainability | Performance | Best For |
|----------|-------------|-------------|-----------------|-------------|----------|
| **YAML Config** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **Multiple sites, non-developers** |
| **Plugin System** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **Complex logic, hot-swapping** |
| **Inheritance** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | **Type safety, simple overrides** |
| **Decorators** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | **Clean code, priority system** |
| **Current (Callbacks)** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | **Simple cases** |

---

## Final Recommendation

### 🏆 Best Overall: **YAML Configuration + Plugin System**

**Hybrid approach combining the best of both**:

1. **YAML for simple rules** (regex patterns, field mappings)
2. **Plugins for complex logic** (custom algorithms)

### Implementation Strategy

```python
class ParserConfig:
    def __init__(self, config_file: str = None, site: str = None, use_plugins: bool = True):
        # Load YAML config first
        if config_file:
            self._load_yaml_config(config_file, site)
        
        # Then load plugins (plugins override YAML)
        if use_plugins and site:
            self._load_plugins(site)
```

### Why This is Superior

1. **Non-developers** can modify YAML for simple changes
2. **Developers** can write plugins for complex logic
3. **Gradual migration** - start with YAML, add plugins as needed
4. **Best of both worlds** - simplicity + power

---

## Migration Path

### Phase 1: Add YAML Support (Week 1)
- Create YAML schema
- Update ParserConfig to read YAML
- Migrate existing extractors to YAML

### Phase 2: Add Plugin System (Week 2)
- Create plugin base class
- Implement plugin loader
- Convert complex extractors to plugins

### Phase 3: Documentation & Testing (Week 3)
- Document YAML schema
- Write plugin development guide
- Create unit tests for both systems

---

## Summary

**Current approach is good**, but these options are **superior** for:

- ✅ **Scalability** - easier to add new sites
- ✅ **Maintainability** - less code changes
- ✅ **Flexibility** - data-driven configuration
- ✅ **Usability** - non-developers can configure

**Recommended**: Implement **YAML configuration** first (biggest ROI), then add **plugin system** if complex logic is needed.
