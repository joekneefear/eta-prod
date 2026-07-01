"""
Configuration management for DTS1000/DTS2000 parser with YAML support.

This module provides configuration for custom field extractors with support
for YAML-based configuration files for site-specific parsing rules.
"""

import os
import re
from typing import Optional, Callable, Dict, Any
from lib.Log import Log
from lib.Util import Util


class Dts1k2kParserConfig:
    """
    Configuration for custom parsing behavior.
    
    Supports both programmatic registration and YAML-based configuration.
    YAML configuration is recommended for site-specific rules.
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
            'device_parser': None,
            'time_parser': None,
            'program_parser': None,
            'process_parser': None,
        }
        
        self.config_data: Dict[str, Any] = {}
        self.site = site
        
        # Load YAML configuration if provided (ensure it's a string path)
        if config_file and isinstance(config_file, str) and os.path.exists(config_file):
            self._load_yaml_config(config_file, site)
    
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
            self.config_data = data.get('defaults', {}).copy()
            
            # Merge site-specific overrides if available
            if site and 'sites' in data and site in data['sites']:
                site_config = data['sites'][site]
                # Deep merge site config into defaults
                for key, value in site_config.items():
                    if isinstance(value, dict) and key in self.config_data and isinstance(self.config_data[key], dict):
                        # Merge dictionaries
                        self.config_data[key].update(value)
                    else:
                        # Override completely
                        self.config_data[key] = value
                Log.INFO(f"Loaded DTS1000 parser config for site: {site} (merged with defaults)")
            else:
                if site:
                    Log.WARN(f"Site '{site}' not found in config, using defaults only")
                else:
                    Log.INFO("Using default DTS1000 parser config")
            
            # Auto-register extractors based on YAML config
            self._auto_register_extractors()
            
        except Exception as e:
            Log.ERROR(f"Failed to load YAML config from {config_file}: {e}")
            Log.INFO("Falling back to default configuration")
    
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
        
        # Register program parser if enabled
        if enabled.get('program_parser'):
            program_config = self.config_data.get('program', {})
            extractor = self._create_program_extractor(program_config)
            if extractor:
                self.register_extractor('program_parser', extractor)
                Log.INFO("Registered custom program parser from YAML config")
        
        # Register time parser if enabled
        if enabled.get('time_parser'):
            timestamp_config = self.config_data.get('timestamp', {})
            extractor = self._create_time_extractor(timestamp_config)
            if extractor:
                self.register_extractor('time_parser', extractor)
                Log.INFO("Registered custom timestamp parser from YAML config")
    
    def _create_lot_extractor(self, config: Dict[str, Any]) -> Optional[Callable]:
        """
        Create lot ID extractor from YAML configuration.
        
        Args:
            config: Lot ID configuration from YAML
            
        Returns:
            Extractor function or None
        """
        pattern_str = config.get('pattern')
        groups = config.get('groups', {})
        fallback_field = config.get('fallback_field', 'LOT')
        
        if not pattern_str:
            return None
        
        try:
            pattern = re.compile(pattern_str)
        except re.error as e:
            Log.ERROR(f"Invalid regex pattern in lot_id config: {e}")
            return None
        
        source = config.get('source', 'content')

        def configured_lot_extractor(raw_data: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
            """Configured lot ID extractor from YAML."""
            lot_string = raw_data.get('LotName', '')
            
            if source == 'filename':
                input_file = context.get('input_file', '')
                if input_file:
                    # Handle both / and \ for cross-platform robustness
                    lot_string = re.split(r'[\\/]', input_file)[-1]
                    # Remove extension
                    lot_string = os.path.splitext(lot_string)[0]
                    Log.INFO(f"Lot extractor: extracted filename '{lot_string}' from path '{input_file}'")

            Log.INFO(f"Lot extractor: attempting to match pattern '{pattern_str}' against '{lot_string}'")
            match = pattern.match(lot_string)
            if match:
                result = {}
                
                # Check if this is 3-part or 4-part format
                # If group 3 (LOT) is None, then group 2 is actually LOT, not OPERATOR
                group_3_val = match.group(3) if len(match.groups()) >= 3 else None
                
                for group_num_str, field_name in groups.items():
                    try:
                        group_num = int(group_num_str)
                        val = match.group(group_num)
                        
                        if val:
                            # Special handling for ambiguous group 2
                            if group_num == 2 and not group_3_val:
                                # 3-part format: FT-Device-Lot
                                # Group 2 is LOT, not OPERATOR
                                result['LOT'] = val
                                Log.INFO(f"Lot extractor: matched group {group_num} -> LOT={val} (3-part format)")
                            else:
                                # Normal mapping
                                result[field_name] = val
                                Log.INFO(f"Lot extractor: matched group {group_num} -> {field_name}={val}")
                    except (ValueError, IndexError) as e:
                        Log.WARN(f"Invalid group mapping in lot_id config: {e}")
                
                if result:
                    Log.INFO(f"Lot extractor matched successfully: {result}")
                    return result
            
            # Fallback
            Log.WARN(f"Lot extractor: no match for '{lot_string}', using fallback field: {fallback_field}")
            return {fallback_field: lot_string}
        
        return configured_lot_extractor
    
    def _create_program_extractor(self, config: Dict[str, Any]) -> Optional[Callable]:
        """
        Create program extractor from YAML configuration.
        
        Args:
            config: Program configuration from YAML
            
        Returns:
            Extractor function or None
        """
        extract_revision = config.get('extract_revision', False)
        revision_position = config.get('revision_position', -1)
        strip_extension = config.get('strip_extension', True)
        fallback_program = config.get('fallback_program', 'UNKNOWN')
        
        def configured_program_extractor(raw_data: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
            """Configured program extractor from YAML."""
            test_filename = raw_data.get('TestFileName', '')
            
            if not test_filename:
                return {'PROGRAM': fallback_program, 'RECIPE_REVISION': ''}
            
            # Get basename (Robustly handle both / and \ regardless of OS)
            basename = re.split(r'[\\/]', test_filename)[-1]
            
            # Strip extension if configured
            if strip_extension:
                basename = os.path.splitext(basename)[0]
            
            # Extract revision if configured
            revision = ''
            program = basename
            
            revision_regex = config.get('revision_regex')
            if revision_regex:
                try:
                    match = re.search(revision_regex, basename)
                    if match:
                        revision = match.group(1) if match.groups() else match.group(0)
                        # Remove revision from program name if it was matched
                        program = basename.replace(match.group(0), '')
                        Log.DEBUG(f"Extracted revision '{revision}' using regex '{revision_regex}'")
                except re.error as e:
                    Log.ERROR(f"Invalid revision_regex '{revision_regex}': {e}")
            
            elif extract_revision and len(basename) > 1:
                try:
                    # Get revision at specified position
                    char_at_pos = basename[revision_position]
                    
                    # If looking at the end (-1), ensure it's alphanumeric (not a symbol like '_')
                    if revision_position == -1 and not char_at_pos.isalnum():
                        # Treat as part of program, no revision
                        revision = ''
                        program = basename
                    else:
                        # Ensure revision is alphanumeric
                        reason = f"char '{char_at_pos}' at pos {revision_position} is alphanumeric"
                        
                        revision = char_at_pos
                        # Remove the revision character from the program name
                        if revision_position == -1:
                            # Remove last character
                            program = basename[:-1]
                        else:
                            # Remove character at specific position
                            program = basename[:revision_position] + basename[revision_position + 1:]
                    
                    Log.DEBUG(f"Extracted revision '{revision}' ({reason}). Program name without revision: '{program}'")
                except IndexError:
                    pass
            
            return {
                'PROGRAM': program,
                'RECIPE': program,
                'RECIPE_REVISION': revision,
            }
        
        return configured_program_extractor
    
    def _create_time_extractor(self, config: Dict[str, Any]) -> Optional[Callable]:
        """
        Create timestamp extractor from YAML configuration.
        
        Args:
            config: Timestamp configuration from YAML
            
        Returns:
            Extractor function or None
        """
        source = config.get('source', 'file_modified')
        time_format = config.get('format', '%Y/%m/%d %H:%M:%S')
        apply_to = config.get('apply_to', ['START_TIME', 'END_TIME'])
        
        def configured_time_extractor(raw_data: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
            """Configured timestamp extractor from YAML."""
            import datetime
            
            timestamp = None
            
            if source == 'file_modified':
                # Get file modification time
                input_file = context.get('input_file')
                if input_file and os.path.exists(input_file):
                    mtime = os.path.getmtime(input_file)
                    timestamp = datetime.datetime.fromtimestamp(mtime)
            
            elif source == 'current':
                # Use current time
                timestamp = datetime.datetime.now()
            
            elif source == 'excel_date':
                # Use date from Excel (handled by default parser)
                return {}
            
            # Format timestamp
            if timestamp:
                formatted_time = timestamp.strftime(time_format)
                result = {}
                for field in apply_to:
                    result[field] = formatted_time
                return result
            
            return {}
        
        return configured_time_extractor
    
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
