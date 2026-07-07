"""
Configuration management for INNO FT XLSX STS8200 parser with YAML support.

This module provides configuration for custom field extractors and parsing rules
with support for YAML-based configuration files for flexible field mapping.
"""

import os
import re
from typing import Optional, Callable, Dict, Any, List
from lib.Log import Log
from lib.Util import Util


class InnoFtXlsxSts8200ParserConfig:
    """
    Configuration for INNO FT XLSX STS8200 custom parsing behavior.
    
    Supports:
    - Header field mapping (label -> model field)
    - Field transformations (trim, regex, uppercase, etc.)
    - Custom extraction functions
    - Default values and fallbacks
    """
    
    def __init__(self, config_file: Optional[str] = None, site: Optional[str] = None):
        """
        Initialize parser configuration.
        
        Args:
            config_file: Path to YAML configuration file (optional)
            site: Site name for site-specific config (optional)
        """
        self.custom_extractors: Dict[str, Optional[Callable]] = {
            'lot_parser': None,
            'header_field_parser': None,
        }
        
        self.config_data: Dict[str, Any] = self._get_default_config()
        self.site = site
        
        # Load YAML configuration if provided
        if config_file and isinstance(config_file, str) and os.path.exists(config_file):
            self._load_yaml_config(config_file, site)
    
    def _get_default_config(self) -> Dict[str, Any]:
        """
        Get default configuration (hardcoded fallback).
        
        Returns:
            Default configuration dictionary
        """
        return {
            'header_labels': {
                'Program': 'RECIPE',
                'Product': 'PRODUCT',
                'WaferModle': 'WAFER_MODEL',
                'LotID': 'LOT',
                'TesterId': 'TESTER_ID',
                'Handler': 'HANDLER',
                'Device Name': 'DEVICE_NAME',
                'Test temp': 'TEST_TEMP',
                'TestDate': 'TEST_DATE',
                'Sub LotID': 'SUB_LOT_ID',
                'Operator ID': 'OPERATOR_ID',
                'START_TIME': 'START_TIME',
                'END_TIME': 'END_TIME',
            },
            'field_transformations': {
                'LOT': {
                    'trim': True,
                    'skip_empty': True,
                    'default': 'NA',
                },
            },
            'test_headers': {
                'test_num_pattern': r'Test\s*#',
                'test_param_pattern': r'Test\s*Parameter',
                'll_limit_pattern': r'^LL',
                'hl_limit_pattern': r'^HL',
                'unit_pattern': r'^Unit',
                'test_table_marker': r'^No',
            },
            'custom_parsers': {
                'lot_parser': False,
                'header_field_parser': False,
            },
        }
    
    def _load_yaml_config(self, config_file: str, site: Optional[str]) -> None:
        """
        Load configuration from YAML file.
        
        Args:
            config_file: Path to YAML configuration file
            site: Site name for site-specific config
        """
        try:
            data = Util.load_yaml(config_file)
            
            # Start with defaults
            base_config = self._get_default_config()
            
            # Merge global config if present
            if 'defaults' in data:
                self._deep_merge(base_config, data['defaults'])
            
            # Merge site-specific overrides if available
            if site and 'sites' in data and site in data['sites']:
                site_config = data['sites'][site]
                self._deep_merge(base_config, site_config)
                Log.INFO(f"Loaded INNO FT XLSX STS8200 parser config for site: {site} (merged with defaults)")
            else:
                if site:
                    Log.WARN(f"Site '{site}' not found in config, using defaults only")
                else:
                    Log.INFO("Using default INNO FT XLSX STS8200 parser config")
            
            self.config_data = base_config
            
            # Auto-register extractors based on YAML config
            self._auto_register_extractors()
            
        except Exception as e:
            Log.ERROR(f"Failed to load YAML config from {config_file}: {e}")
            Log.INFO("Falling back to default configuration")
    
    def _deep_merge(self, target: Dict[str, Any], source: Dict[str, Any]) -> None:
        """
        Deep merge source dict into target dict.
        
        Args:
            target: Target dictionary to merge into
            source: Source dictionary to merge from
        """
        for key, value in source.items():
            if isinstance(value, dict) and key in target and isinstance(target[key], dict):
                self._deep_merge(target[key], value)
            else:
                target[key] = value
    
    def _auto_register_extractors(self) -> None:
        """Automatically register extractors based on YAML configuration."""
        enabled = self.config_data.get('custom_parsers', {})
        
        # Register lot parser if enabled
        if enabled.get('lot_parser'):
            lot_config = self.config_data.get('lot_id', {})
            extractor = self._create_lot_extractor(lot_config)
            if extractor:
                self.register_extractor('lot_parser', extractor)
                Log.INFO("Registered custom lot ID parser from YAML config")
        
        # Register header field parser if enabled
        if enabled.get('header_field_parser'):
            field_config = self.config_data.get('header_field', {})
            extractor = self._create_header_field_extractor(field_config)
            if extractor:
                self.register_extractor('header_field_parser', extractor)
                Log.INFO("Registered custom header field parser from YAML config")
    
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
        source = config.get('source', 'header_field')  # 'header_field' or 'filename'
        field_label = config.get('field_label', 'LotID')  # Which header label contains LOT
        pattern_str = config.get('pattern')
        groups = config.get('groups', {})
        transformations = config.get('transformations', {})
        fallback_value = config.get('fallback', 'NA')
        
        def configured_lot_extractor(raw_header: Dict[str, Any], model_field: str) -> Optional[str]:
            """
            Extract and transform lot ID based on YAML config.
            
            Args:
                raw_header: Raw header dictionary from parser
                model_field: Target model field name (e.g., 'LOT')
                
            Returns:
                Extracted and transformed value, or fallback
            """
            lot_value = raw_header.get(field_label, '')
            
            # Apply pattern matching if configured
            if pattern_str:
                try:
                    pattern = re.compile(pattern_str)
                    match = pattern.search(str(lot_value))
                    if match and groups:
                        # Extract from regex group
                        for group_num_str, target_field in groups.items():
                            try:
                                group_num = int(group_num_str)
                                extracted = match.group(group_num)
                                if target_field == model_field and extracted:
                                    lot_value = extracted
                                    Log.DEBUG(f"Lot extractor: matched group {group_num} -> {extracted}")
                                    break
                            except (ValueError, IndexError):
                                pass
                except re.error as e:
                    Log.ERROR(f"Invalid regex pattern in lot extractor: {e}")
            
            # Apply transformations
            lot_value = self._apply_transformations(str(lot_value), transformations)
            
            # Apply model-field-specific transformations if configured
            field_transforms = self.config_data.get('field_transformations', {}).get(model_field, {})
            lot_value = self._apply_transformations(lot_value, field_transforms)
            
            # Return value or fallback
            if lot_value and lot_value.upper() != 'NA':
                Log.DEBUG(f"Lot extractor: extracted '{lot_value}'")
                return lot_value
            
            Log.DEBUG(f"Lot extractor: no valid value found, using fallback '{fallback_value}'")
            return fallback_value
        
        return configured_lot_extractor
    
    def _create_header_field_extractor(self, config: Dict[str, Any]) -> Optional[Callable]:
        """
        Create generic header field extractor from YAML configuration.
        
        Supports:
        - Field label mapping (Excel label -> model field)
        - Value transformations (trim, case conversion, regex)
        - Default/fallback values
        
        Args:
            config: Header field configuration from YAML
            
        Returns:
            Extractor function or None
        """
        def configured_header_field_extractor(
            raw_header: Dict[str, Any],
            field_label: str,
            model_field: str
        ) -> Optional[str]:
            """
            Extract and transform header field based on YAML config.
            
            Args:
                raw_header: Raw header dictionary from parser
                field_label: Label in Excel header (e.g., 'Program')
                model_field: Target model field name (e.g., 'RECIPE')
                
            Returns:
                Extracted and transformed value
            """
            value = raw_header.get(field_label, '')
            
            # Apply generic transformations
            transformations = self.config_data.get('field_transformations', {}).get(
                model_field, {}
            )
            value = self._apply_transformations(str(value), transformations)
            
            # Apply fallback if empty
            if not value or value.upper() == 'NA':
                value = transformations.get('default', 'NA')
            
            return value
        
        return configured_header_field_extractor
    
    def _apply_transformations(self, value: str, transforms: Dict[str, Any]) -> str:
        """
        Apply a series of transformations to a value.
        
        Supported transformations:
        - trim: Strip whitespace
        - uppercase: Convert to uppercase
        - lowercase: Convert to lowercase
        - regex: Apply regex substitution {pattern, replacement}
        - skip_if_empty: Return as-is if empty
        
        Args:
            value: Value to transform
            transforms: Dictionary of transformations to apply
            
        Returns:
            Transformed value
        """
        if not transforms:
            return value
        
        # Trim whitespace
        if transforms.get('trim', False):
            value = value.strip()
        
        # Skip if empty check
        if transforms.get('skip_empty', False) and not value:
            return ''
        
        # Uppercase
        if transforms.get('uppercase', False):
            value = value.upper()
        
        # Lowercase
        if transforms.get('lowercase', False):
            value = value.lower()
        
        # Regex substitution
        regex_config = transforms.get('regex')
        if regex_config and isinstance(regex_config, dict):
            pattern = regex_config.get('pattern')
            replacement = regex_config.get('replacement', '')
            flags_str = regex_config.get('flags', '')
            
            if pattern:
                try:
                    flags = 0
                    if 'IGNORECASE' in flags_str:
                        flags |= re.IGNORECASE
                    if 'MULTILINE' in flags_str:
                        flags |= re.MULTILINE
                    value = re.sub(pattern, replacement, value, flags=flags)
                except re.error as e:
                    Log.WARN(f"Invalid regex in transformation: {e}")
        
        return value
    
    def get_header_labels(self) -> Dict[str, str]:
        """
        Get header label to model field mapping.
        
        Returns:
            Dictionary mapping Excel labels to model fields
        """
        return self.config_data.get('header_labels', {})
    
    def get_test_header_patterns(self) -> Dict[str, str]:
        """
        Get regex patterns for test header detection.
        
        Returns:
            Dictionary of pattern names to regex strings
        """
        return self.config_data.get('test_headers', {})
    
    def register_extractor(self, field_name: str, callback: Callable) -> None:
        """
        Register a custom extraction function.
        
        Args:
            field_name: Name of the field to extract
            callback: Extraction function
        """
        if field_name not in self.custom_extractors:
            self.custom_extractors[field_name] = None
        
        self.custom_extractors[field_name] = callback
    
    def has_extractor(self, field_name: str) -> bool:
        """
        Check if a custom extractor is registered.
        
        Args:
            field_name: Name of the field
            
        Returns:
            True if extractor is registered
        """
        return field_name in self.custom_extractors and self.custom_extractors[field_name] is not None
    
    def get_extractor(self, field_name: str) -> Optional[Callable]:
        """
        Get a registered extractor function.
        
        Args:
            field_name: Name of the field
            
        Returns:
            Extractor function or None
        """
        return self.custom_extractors.get(field_name)
