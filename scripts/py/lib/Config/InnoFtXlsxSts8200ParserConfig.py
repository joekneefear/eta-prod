"""
Configuration management for INNO FT XLSX STS8200 parser with YAML support.

This module provides configuration for custom field extractors and parsing rules
with support for YAML-based configuration files for flexible field mapping.
"""

import os
import re
from typing import Optional, Dict, Any
from lib.Log import Log
from lib.Util import Util


class InnoFtXlsxSts8200ParserConfig:
    """
    Configuration for INNO FT XLSX STS8200 parser.
    
    Loads site-specific parsing rules from YAML configuration:
    - header_labels: Excel column A labels to extract (per-site configurable)
    - test_headers: Regex patterns for identifying test metadata rows
    - field_transformations: Post-extraction value transformations
    
    Supports multi-site configuration where different sites can have different
    Excel column layouts and parsing rules.
    """
    
    def __init__(self, config_file: Optional[str] = None, site: Optional[str] = None):
        """
        Initialize parser configuration.
        
        Args:
            config_file: Path to YAML configuration file (optional)
            site: Site name for site-specific config (optional)
        """
        self.config_data: Dict[str, Any] = self._get_default_config()
        self.site = site
        
        # Load YAML configuration if provided
        if config_file and isinstance(config_file, str) and os.path.exists(config_file):
            self._load_yaml_config(config_file, site)
    
    def _get_default_config(self) -> Dict[str, Any]:
        """
        Get default configuration (hardcoded fallback).
        
        Defines:
        - header_labels: Excel column A labels that the parser should extract
        - test_headers: Regex patterns for identifying test header rows
        - field_transformations: Post-extraction transformations (trim, default values, etc.)
        
        Returns:
            Default configuration dictionary
        """
        return {
            'header_labels': {
                'Program',
                'Product',
                'WaferModle',
                'LotID',
                'TesterId',
                'Handler',
                'Device Name',
                'Test temp',
                'TestDate',
                'Sub LotID',
                'Operator ID',
            },
            'test_headers': {
                'test_num_pattern': r'Test\s*#',
                'test_param_pattern': r'Test\s*Parameter',
                'll_limit_pattern': r'^LL$',
                'hl_limit_pattern': r'^HL$',
                'unit_pattern': r'^Unit$',
                'test_table_marker': r'^No$',
            },
            'field_transformations': {
                'LotID': {
                    'trim': True,
                    'skip_empty': True,
                    'default': 'NA',
                },
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
            
            # Merge DEFAULT config if present
            if 'DEFAULT' in data and isinstance(data['DEFAULT'], dict):
                self._deep_merge(base_config, data['DEFAULT'])
                Log.INFO("Merged DEFAULT parser config")
            
            # Merge site-specific overrides if available
            if site and site in data and site != 'DEFAULT' and isinstance(data[site], dict):
                site_config = data[site]
                self._deep_merge(base_config, site_config)
                Log.INFO(f"Loaded INNO FT XLSX STS8200 parser config for site: {site} (merged with defaults)")
            else:
                if site:
                    Log.WARN(f"Site '{site}' not found in config, using defaults only")
            
            self.config_data = base_config
            
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
            elif isinstance(value, (list, set)):
                # For lists and sets, replace entirely
                target[key] = value
            else:
                target[key] = value
    def get_header_labels(self) -> set:
        """
        Get set of header labels to extract from Excel column A.
        
        Returns:
            Set of header label strings (e.g., 'Program', 'LotID', 'Test temp')
        """
        labels = self.config_data.get('header_labels', set())
        if isinstance(labels, dict):
            return set(labels.keys())
        return set(labels) if labels else set()
    
    def get_test_header_patterns(self) -> Dict[str, str]:
        """
        Get regex patterns for test header detection.
        
        Returns:
            Dictionary of pattern names to regex strings
        """
        return self.config_data.get('test_headers', {})
