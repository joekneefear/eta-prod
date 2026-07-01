"""
SYNOPSIS
    Klarf 1.8 Enricher (Site-Aware)

DESCRIPTION
    Class to enrich Klarf 1.8 files with a <Metadata> section.
    Logic is driven by a multi-site YAML configuration file.

AUTHOR
    jgarcia

CHANGES
    2026-Feb-16 - initial
    2026-Feb-16 - refactor to use YAML config
    2026-Feb-16 - added site-awareness support
"""

import re
from lib.Log import Log
from lib.Data.MetadataDTO import MetadataDTO

DEFAULT_SCRIBE_WAFER_RECORD_REGEX = r'^([A-Z0-9]+)-(\d{2})\s[A-Z0-9]{2}$'
DEFAULT_SCRIBE_WAFER_RECORD_REPLACEMENT = r'\1_\2'

class Klarf18Enricher:
    def __init__(self, metadata, original_content, config=None, site="DEFAULT", lot_metadata=None):
        self.metadata = metadata
        self.original_content = original_content
        self.config = config or {}
        self.site = site or "DEFAULT"
        self.lot_metadata = lot_metadata or {}
        self._refdb_direct_found = 0
        self._refdb_insensitive_found = 0
        self._refdb_missing = 0
        self._fallback_used = 0
        Log.INFO(f"Enricher initialized for site '{self.site}'. RefDB Keys: {list(self.lot_metadata.keys())}")

    def generate_metadata_xml(self):
        """
        Generates the <Metadata> XML section using MetadataDTO and YAML config.
        """
        try:
            self._refdb_direct_found = 0
            self._refdb_insensitive_found = 0
            self._refdb_missing = 0
            self._fallback_used = 0

            mapping = self._apply_mapping()
            metadata_dto = MetadataDTO()
            
            Log.INFO(f"Generating metadata XML with {len(mapping)} fields")

            for yaml_key, data in mapping.items():
                val = str(data.get('value', "NA")).strip()
                if not val: val = "NA"
                
                src = data.get('source', "KLARF_1.8")
                # Use target from mapping, or fallback to the yaml_key
                target = data.get('target', yaml_key)
                
                # Resolve the target to the MetadataDTO constant value if it exists
                dto_attr_name = getattr(MetadataDTO, target, target)
                
                # Log to file only, don't persist to database (too verbose)
                Log.DEBUG(f"Set Metadata: target='{dto_attr_name}' (from '{target}'), value='{val}', source='{src}'")
                metadata_dto.set_metadata_self_attribute(dto_attr_name, source=src, value=val)

            if self._refdb_direct_found or self._refdb_insensitive_found or self._refdb_missing or self._fallback_used:
                Log.INFO(
                    f"RefDB resolution summary: direct_found={self._refdb_direct_found}, "
                    f"insensitive_found={self._refdb_insensitive_found}, missing={self._refdb_missing}, "
                    f"fallback_used={self._fallback_used}"
                )
            
            xml = metadata_dto.generate_metadata_xml(data={})
            Log.INFO(f"Metadata XML generation completed")
            return xml
            
        except Exception as e:
            Log.ERROR(f"Error generating metadata XML: {e}")
            raise

    def enrich(self):
        """
        Returns the enriched content (Metadata + original content).
        """
        metadata_xml = self.generate_metadata_xml()
        return metadata_xml + "\n" + self.original_content

    def _apply_mapping(self):
        """
        Resolves mapping rules from YAML configuration based on the selected site.
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
            # Carry over the target from the rule to the result
            resolved['target'] = rule.get('target', attr_name)
            results[attr_name] = resolved

        return results

    def _resolve_rule(self, rule):
        res = self._do_resolve(rule)
        
        # Support fallback if the value is NA or empty
        val_check = str(res.get('value', "NA")).strip()
        if (val_check == "NA" or not val_check) and 'fallback' in rule:
            self._fallback_used += 1
            Log.DEBUG(f"Result NA. Trying fallback rule.")
            res = self._resolve_rule(rule['fallback'])
            
        return res

    def _do_resolve(self, rule):
        rtype = rule.get('type')
        source = rule.get('source')
        meta_source = rule.get('meta_source')
        
        if not meta_source:
            if rtype == 'constant':
                meta_source = "SCRIPT_CONSTANT"
            elif rtype == 'refdb':
                meta_source = "ERT_REFDB"
            else:
                meta_source = "KLARF_1.8"
        
        val = "NA"
        raw_data = None
        altered = False

        # 1. Extraction Phase
        if rtype == 'constant':
            val = rule.get('value', "NA")
        elif rtype in ['record', 'field']:
            raw_data = self._find_in_metadata(self.metadata, source)
            if raw_data is not None:
                if isinstance(raw_data, dict) and '_val' in raw_data:
                    val = raw_data['_val']
                elif isinstance(raw_data, list):
                    index = rule.get('index', 0)
                    if index < len(raw_data):
                        item = raw_data[index]
                        val = item.get('_val', str(item)) if isinstance(item, dict) else str(item)
                    else:
                        val = "NA"
                else:
                    val = str(raw_data)
        elif rtype == 'refdb':
            # Use recursive lookup for ERT metadata to handle both flat and nested responses
            raw_data = self._find_in_metadata(self.lot_metadata, source)
            if raw_data is not None:
                val = str(raw_data)
                # Normalize sourceLot-like values: if the mapping will append a '.S' via format,
                # strip any existing trailing '.S' from the RefDB value to avoid double-suffix.
                fmt = rule.get('format', '')
                if fmt and '.S' in fmt:
                    val = re.sub(r'\.S$', '', val, flags=re.IGNORECASE)
                self._refdb_direct_found += 1
                Log.DEBUG(f"RefDB Found: {source} = '{val}'")
            else:
                Log.DEBUG(f"RefDB Not Found: {source} (Attempting Case-Insensitive)")
                # Fallback: case-insensitive search if direct match fails
                val_raw = self._find_in_metadata_case_insensitive(self.lot_metadata, source)
                if val_raw is not None:
                    val = str(val_raw)
                    fmt = rule.get('format', '')
                    if fmt and '.S' in fmt:
                        val = re.sub(r'\.S$', '', val, flags=re.IGNORECASE)
                    raw_data = val_raw
                    self._refdb_insensitive_found += 1
                    Log.DEBUG(f"RefDB Found (insensitive): {source} -> '{val}'")
                else:
                    self._refdb_missing += 1
                    Log.DEBUG(f"RefDB Lookup Failed for '{source}'")

        elif rtype == 'wafer_record':
            wafer_record_key = source or 'WaferRecord'
            source_lot_refdb_key = rule.get('source_lot_refdb_source')
            source_lot_key = rule.get('source_lot_source', 'LotRecord')
            construction_mode = rule.get('construction_mode', 'auto')
            scribe_regex = rule.get('scribe_regex', DEFAULT_SCRIBE_WAFER_RECORD_REGEX)
            scribe_replacement = rule.get('scribe_replacement', DEFAULT_SCRIBE_WAFER_RECORD_REPLACEMENT)
            scribe_wafer_group = int(rule.get('scribe_wafer_group', 2))

            wafer_record_raw = self._find_in_metadata(self.metadata, wafer_record_key)
            wafer_record = self._extract_scalar_value(wafer_record_raw)
            val = self._resolve_wafer_record(
                wafer_record=wafer_record,
                source_lot_refdb_key=source_lot_refdb_key,
                source_lot_key=source_lot_key,
                construction_mode=construction_mode,
                scribe_regex=scribe_regex,
                scribe_replacement=scribe_replacement,
                scribe_wafer_group=scribe_wafer_group,
            )

            if val != "NA":
                altered = True

        elif rtype == 'composite':
            template = rule.get('template', "")
            parts_config = rule.get('parts', {})
            parts_vals = {}
            for p_name, p_rule in parts_config.items():
                resolved = self._resolve_rule(p_rule)
                parts_vals[p_name] = str(resolved.get('value', "NA")).strip()
                if str(resolved.get('source')) == "Klarf_1.8_CORRECTION":
                    altered = True
            try:
                val = template.format(**parts_vals)
            except Exception as e:
                Log.ERROR(f"Error formatting composite metadata {template}: {e}")
                val = "NA"
            altered = True 

        # 2. Transformation Phase (Universal)
        if val is None: val = "NA"
        
        if val != "NA" and rtype != 'composite':
            # Apply Slice
            if 'slice' in rule:
                s = rule['slice']
                val = str(val)[s[0]:s[1]]
                altered = True
            
            # Apply Format
            if 'format' in rule:
                # If we have a list (field/record), use it directly. 
                # If we have a single value (refdb/constant), treat it as a single-element list.
                fmt_args = raw_data if isinstance(raw_data, list) else [val]
                clean_args = [str(x).strip() for x in fmt_args]
                try:
                    val = rule['format'].format(*clean_args)
                    altered = True
                except Exception as e:
                    Log.ERROR(f"Format error for {source}: {e}")

            # Apply Regex Replace
            if 'regex_replace' in rule:
                pattern, replacement = rule['regex_replace']
                new_val = re.sub(pattern, replacement, str(val))
                if str(new_val) != str(val):
                    val = new_val
                    altered = True

        if altered and meta_source == "KLARF_1.8":
            meta_source = "Klarf_1.8_CORRECTION"

        return {'value': val, 'source': meta_source}

    def _extract_scalar_value(self, raw_data):
        if raw_data is None:
            return None
        if isinstance(raw_data, dict):
            if '_val' in raw_data:
                return raw_data.get('_val')
            return str(raw_data)
        if isinstance(raw_data, list):
            if not raw_data:
                return None
            first = raw_data[0]
            if isinstance(first, dict):
                return first.get('_val', str(first))
            return first
        return raw_data

    def _normalize_source_lot(self, lot_value):
        if lot_value is None:
            return ""
        lot = str(lot_value).strip()
        if not lot:
            return ""
        return re.sub(r'\.S$', '', lot, flags=re.IGNORECASE)

    def _resolve_wafer_record(
        self,
        wafer_record,
        source_lot_refdb_key=None,
        source_lot_key='LotRecord',
        construction_mode='auto',
        scribe_regex=DEFAULT_SCRIBE_WAFER_RECORD_REGEX,
        scribe_replacement=DEFAULT_SCRIBE_WAFER_RECORD_REPLACEMENT,
        scribe_wafer_group=2,
    ):
        if wafer_record is None:
            return "NA"

        wafer_record_text = str(wafer_record).strip()
        if not wafer_record_text:
            return "NA"

        wafer_record_upper = wafer_record_text.upper()

        if construction_mode == 'source_lot_wafer_number':
            try:
                if re.fullmatch(scribe_regex, wafer_record_upper):
                    return re.sub(scribe_regex, scribe_replacement, wafer_record_upper)
            except re.error as re_err:
                Log.WARN(
                    f"Invalid wafer_record scribe regex '{scribe_regex}': {re_err}. Using default pattern."
                )
                if re.fullmatch(DEFAULT_SCRIBE_WAFER_RECORD_REGEX, wafer_record_upper):
                    return re.sub(
                        DEFAULT_SCRIBE_WAFER_RECORD_REGEX,
                        DEFAULT_SCRIBE_WAFER_RECORD_REPLACEMENT,
                        wafer_record_upper,
                    )

            if not re.fullmatch(r'\d{1,3}', wafer_record_text):
                Log.WARN(
                    f"WaferRecord '{wafer_record_text}' is neither scribe-matching nor numeric for source_lot_wafer_number mode; returning NA"
                )
                return "NA"

            wafer_num = str(int(wafer_record_text)).zfill(2)

            source_lot = self._resolve_source_lot(
                source_lot_refdb_key=source_lot_refdb_key,
                source_lot_key=source_lot_key,
            )
            if not source_lot:
                Log.WARN(
                    f"WaferRecord '{wafer_record_text}' requires source-lot construction but source lot is missing in both RefDB '{source_lot_refdb_key}' and file '{source_lot_key}'; returning NA"
                )
                return "NA"

            return f"{source_lot}_{wafer_num}"

        try:
            if re.fullmatch(scribe_regex, wafer_record_upper):
                return re.sub(scribe_regex, scribe_replacement, wafer_record_upper)
        except re.error as re_err:
            Log.WARN(
                f"Invalid wafer_record scribe regex '{scribe_regex}': {re_err}. Using default pattern."
            )
            if re.fullmatch(DEFAULT_SCRIBE_WAFER_RECORD_REGEX, wafer_record_upper):
                return re.sub(
                    DEFAULT_SCRIBE_WAFER_RECORD_REGEX,
                    DEFAULT_SCRIBE_WAFER_RECORD_REPLACEMENT,
                    wafer_record_upper,
                )

        if re.fullmatch(r'\d{1,3}', wafer_record_text):
            wafer_num = str(int(wafer_record_text)).zfill(2)
            source_lot = self._resolve_source_lot(
                source_lot_refdb_key=source_lot_refdb_key,
                source_lot_key=source_lot_key,
            )

            if not source_lot:
                Log.WARN(
                    f"WaferRecord '{wafer_record_text}' is numeric but source lot is missing in both RefDB '{source_lot_refdb_key}' and file '{source_lot_key}'; returning NA"
                )
                return "NA"
            return f"{source_lot}_{wafer_num}"

        return wafer_record_text

    def _resolve_source_lot(self, source_lot_refdb_key=None, source_lot_key='LotRecord'):
        source_lot = ""

        if source_lot_refdb_key:
            source_lot_refdb_raw = self._find_in_metadata(self.lot_metadata, source_lot_refdb_key)
            source_lot = self._normalize_source_lot(self._extract_scalar_value(source_lot_refdb_raw))

        if not source_lot:
            source_lot_raw = self._find_in_metadata(self.metadata, source_lot_key)
            source_lot = self._normalize_source_lot(self._extract_scalar_value(source_lot_raw))

        return source_lot

    def _extract_wafer_number(self, wafer_record_text, scribe_regex, scribe_wafer_group=2):
        if re.fullmatch(r'\d{1,3}', wafer_record_text):
            return str(int(wafer_record_text)).zfill(2)

        try:
            scribe_match = re.fullmatch(scribe_regex, wafer_record_text.upper())
            if scribe_match:
                wafer_number_raw = scribe_match.group(scribe_wafer_group)
                if re.fullmatch(r'\d{1,3}', str(wafer_number_raw)):
                    return str(int(str(wafer_number_raw))).zfill(2)
        except (re.error, IndexError):
            return None

        return None

    def _find_in_metadata(self, data, key):
        """
        Recursively find a key (Record or Field) in a dictionary.
        """
        if not data or not isinstance(data, dict): return None
        
        # Check direct key
        if key in data:
            return data[key]
        
        # Search deeper
        for k, v in data.items():
            if k.startswith("_"): continue # Skip internal keys
            
            if isinstance(v, dict):
                res = self._find_in_metadata(v, key)
                if res is not None: return res
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        res = self._find_in_metadata(item, key)
                        if res is not None: return res
        return None

    def _find_in_metadata_case_insensitive(self, data, key):
        """
        Recursively find a key in a dictionary using case-insensitive comparison.
        """
        if not data or not isinstance(data, dict): return None
        
        # Check direct keys (case insensitive)
        for k, v in data.items():
            if k.lower() == key.lower():
                return v
        
        # Search deeper
        for k, v in data.items():
            if k.startswith("_"): continue
            
            if isinstance(v, dict):
                res = self._find_in_metadata_case_insensitive(v, key)
                if res is not None: return res
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        res = self._find_in_metadata_case_insensitive(item, key)
                        if res is not None: return res
        return None

