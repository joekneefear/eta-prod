"""
SYNOPSIS
    INNO FT XLSX Enricher (Site-Aware)

DESCRIPTION
    Class to enrich INNO FT XLSX parsed data with metadata fields.
    Logic is driven by a multi-site YAML configuration file.
    Maps raw_header and RefDB fields to Model.header attributes.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jul-02 - Initial implementation

LICENSE
    (C) onsemi 2026 All rights reserved.
"""

import re
from lib.Log import Log
from lib.Util import Util


class InnoFtXlsxSts8200Enricher:
    """
    Enricher for INNO FT XLSX data.
    
    Applies YAML-driven field mapping rules to resolve metadata fields
    from raw xlsx header and RefDB data, then writes them to Model.header.
    """
    
    # Mapping from YAML field name to Model.header attribute name
    FIELD_TO_ATTR = {
        'AlternateProduct': 'ALTERNATE_PRODUCT',
        'EndTime': 'END_TIME',
        'Fab': 'FAB',
        'LotId': 'LOT',
        'Handler': 'HANDLER',
        'MeasuringEquipment': 'MEASURING_EQUIPMENT',
        'ProcessingStep': 'PROCESSING_STEP',
        'Product': 'PRODUCT',
        'Program': 'PROGRAM',
        'TestFacility': 'TEST_FACILITY',
        'Recipe': 'RECIPE',
        'RecipeRevision': 'RECIPE_REVISION',
        'TesterSoftware': 'TESTER_SOFTWARE',
        'TesterSoftwareVersion': 'TESTER_SOFTWARE_VERSION',
        'SourceLot': 'SOURCE_LOT',
        'StartTime': 'START_TIME',
        'WaferId': 'SCRIBE_ID',
        'SubconLotId': 'SUBCON_LOT',
        'Operator': 'OPERATOR',
    }
    
    def __init__(self, raw_header, model, config=None, site="DEFAULT", lot_metadata=None):
        """
        Initialize enricher.
        
        Args:
            raw_header: Dict of parsed xlsx header fields (label: value)
            model: Model object to enrich (writes to model.header)
            config: YAML configuration dict
            site: Site name for YAML config selection
            lot_metadata: Dict of RefDB on_lot response data
        """
        self.raw_header = raw_header or {}
        self.model = model
        self.config = config or {}
        self.site = site or "DEFAULT"
        self.lot_metadata = lot_metadata or {}
        
        self._refdb_direct_found = 0
        self._refdb_insensitive_found = 0
        self._refdb_missing = 0
        self._fallback_used = 0
        
        Log.INFO(f"Enricher initialized for site '{self.site}'. "
                f"RefDB Keys: {list(self.lot_metadata.keys())}")
    
    def enrich(self) -> object:
        """
        Apply mapping rules and enrich model.header with resolved fields.
        
        Returns:
            The model object (modified in place)
        """
        try:
            self._refdb_direct_found = 0
            self._refdb_insensitive_found = 0
            self._refdb_missing = 0
            self._fallback_used = 0
            
            mapping = self._apply_mapping()
            
            Log.INFO(f"Enriching with {len(mapping)} fields")
            
            # Apply resolved values to model.header
            for yaml_key, data in mapping.items():
                val = str(data.get('value', 'NA')).strip()
                if not val:
                    val = 'NA'
                
                # Get target attribute name
                target_attr = self.FIELD_TO_ATTR.get(yaml_key, yaml_key)
                
                Log.DEBUG(f"Set {target_attr}='{val}' (from {yaml_key})")
                setattr(self.model.header, target_attr, val)
            
            # Log summary
            if (self._refdb_direct_found or self._refdb_insensitive_found or 
                self._refdb_missing or self._fallback_used):
                Log.INFO(
                    f"RefDB resolution summary: direct_found={self._refdb_direct_found}, "
                    f"insensitive_found={self._refdb_insensitive_found}, "
                    f"missing={self._refdb_missing}, fallback_used={self._fallback_used}"
                )
            
            Log.INFO("Enrichment completed")
            return self.model
        
        except Exception as e:
            Log.ERROR(f"Error during enrichment: {e}")
            raise
    
    def _apply_mapping(self):
        """
        Resolve mapping rules from YAML configuration.
        
        Returns:
            Dict mapping yaml_key -> {'value': resolved_value, 'source': source_name}
        """
        if not self.config:
            Log.WARN("No YAML configuration provided. Returning empty mapping.")
            return {}
        
        # Select site configuration
        site_config = self.config.get(self.site, {})
        default_config = self.config.get("DEFAULT", {})
        
        if not site_config and not default_config:
            Log.WARN(f"Site '{self.site}' and 'DEFAULT' both not found in configuration.")
            return {}
        
        # Merge fields with DEFAULT as baseline
        merged_fields = {}
        if default_config:
            merged_fields.update(default_config.get('fields', {}))
        if site_config:
            merged_fields.update(site_config.get('fields', {}))
        
        results = {}
        for attr_name, rule in merged_fields.items():
            resolved = self._resolve_rule(rule)
            results[attr_name] = resolved
        
        return results
    
    def _resolve_rule(self, rule):
        """
        Resolve a single YAML rule, with fallback support.
        
        Args:
            rule: YAML rule dict
            
        Returns:
            Dict with 'value' and 'source'
        """
        res = self._do_resolve(rule)
        
        # Support fallback if value is NA or empty
        val_check = str(res.get('value', 'NA')).strip()
        if (val_check == 'NA' or not val_check) and 'fallback' in rule:
            self._fallback_used += 1
            Log.DEBUG("Result NA. Trying fallback rule.")
            res = self._resolve_rule(rule['fallback'])
        
        return res
    
    def _do_resolve(self, rule):
        """
        Core resolution logic: extract and transform a field value.
        
        Args:
            rule: YAML rule dict with type, source, transforms, etc.
            
        Returns:
            Dict with 'value' (str) and 'source' (str)
        """
        rtype = rule.get('type')
        source = rule.get('source')
        
        # Determine source name for logging
        if rtype == 'constant':
            meta_source = 'SCRIPT_CONSTANT'
        elif rtype == 'refdb':
            meta_source = 'ERT_REFDB'
        else:
            meta_source = 'XLSX_HEADER'
        
        val = 'NA'
        
        # 1. Extraction Phase
        if rtype == 'constant':
            val = rule.get('value', 'NA')
        
        elif rtype == 'field':
            # Read from raw_header dict
            val = self.raw_header.get(source, 'NA')
            if val:
                val = str(val).strip()
                if not val:
                    val = 'NA'
        
        elif rtype == 'refdb':
            # Read from lot_metadata dict
            if not self.lot_metadata:
                Log.WARN(f"RefDB lookup for '{source}' skipped: lot_metadata is empty (no RefDB call made or no data returned)")
            val = self._find_in_metadata(self.lot_metadata, source)
            if val is not None:
                val = str(val).strip()
                # Strip any trailing .S if format will append it (avoid double suffix)
                fmt = rule.get('format', '')
                if fmt and '.S' in fmt:
                    val = re.sub(r'\.S$', '', val, flags=re.IGNORECASE)
                self._refdb_direct_found += 1
                Log.DEBUG(f"RefDB Found: {source} = '{val}'")
            else:
                Log.DEBUG(f"RefDB Not Found: {source} (attempting case-insensitive)")
                val_raw = self._find_in_metadata_case_insensitive(self.lot_metadata, source)
                if val_raw is not None:
                    val = str(val_raw).strip()
                    fmt = rule.get('format', '')
                    if fmt and '.S' in fmt:
                        val = re.sub(r'\.S$', '', val, flags=re.IGNORECASE)
                    self._refdb_insensitive_found += 1
                    Log.DEBUG(f"RefDB Found (insensitive): {source} -> '{val}'")
                else:
                    self._refdb_missing += 1
                    Log.DEBUG(f"RefDB Lookup Failed for '{source}'")
                    val = 'NA'
        
        # 2. Transformation Phase
        if val is None:
            val = 'NA'
        
        if val != 'NA':
            # Apply regex_replace
            if 'regex_replace' in rule:
                pattern, replacement = rule['regex_replace']
                new_val = re.sub(pattern, replacement, str(val))
                if str(new_val) != str(val):
                    val = new_val
            
            # Apply format
            if 'format' in rule:
                try:
                    val = rule['format'].format(val)
                except Exception as e:
                    Log.ERROR(f"Format error for {source}: {e}")
            
            # Apply slice
            if 'slice' in rule:
                s = rule['slice']
                val = str(val)[s[0]:s[1]]

            # Normalize date fields to YYYY/MM/DD HH:MM:SS
            if rule.get('normalize_date'):
                try:
                    val = Util.convert_date_format_to_yyyymmdd_hms(val)
                except Exception as e:
                    Log.WARN(f"Date normalization failed for '{val}': {e}")
        
        return {'value': val, 'source': meta_source}
    
    def _find_in_metadata(self, data, key):
        """
        Recursively find a key in a nested dictionary.
        
        Args:
            data: Dict to search
            key: Key to find
            
        Returns:
            Value if found, None otherwise
        """
        if not data or not isinstance(data, dict):
            return None
        
        # Direct key match
        if key in data:
            return data[key]
        
        # Recursive search
        for k, v in data.items():
            if k.startswith('_'):
                continue
            
            if isinstance(v, dict):
                res = self._find_in_metadata(v, key)
                if res is not None:
                    return res
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        res = self._find_in_metadata(item, key)
                        if res is not None:
                            return res
        
        return None
    
    def _find_in_metadata_case_insensitive(self, data, key):
        """
        Recursively find a key in a nested dictionary (case-insensitive).
        
        Args:
            data: Dict to search
            key: Key to find (case-insensitive)
            
        Returns:
            Value if found, None otherwise
        """
        if not data or not isinstance(data, dict):
            return None
        
        # Direct key match (case-insensitive)
        key_lower = key.lower()
        for k, v in data.items():
            if k.lower() == key_lower:
                return v
        
        # Recursive search
        for k, v in data.items():
            if k.startswith('_'):
                continue
            
            if isinstance(v, dict):
                res = self._find_in_metadata_case_insensitive(v, key)
                if res is not None:
                    return res
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        res = self._find_in_metadata_case_insensitive(item, key)
                        if res is not None:
                            return res
        
        return None
