#!/usr/bin/env python3.12

"""
SYNOPSIS
    Klarf 1.8 WMC (Wafer Map Config) Enricher using FJM

DESCRIPTION
    This script processes a Klarf 1.8 file, extracts existing metadata and wafer map limits,
    parses a corresponding FJM layout file using FJMParser, calculates wafer map configuration 
    offsets, and prepends the updated <Metadata> block back to the Klarf file.

AUTHOR
    junifferallan.garcia@onsemi.com / Antigravity pair programming

CHANGES
    2026-Jun-16 - Initial version focusing on wafer map configuration enrichment from FJM.
"""

import os
import sys
import re
import gzip
from lib.Log import Log
from lib.Util import Util
from lib.Utility.JndUtil import JndUtil
from lib.Writer import Writer
from lib.Data.MetadataDTO import MetadataDTO
from lib.Parser.FJMParser import FJMParser
from lib.Data.Wmap import Wmap
from lib.PPLogger import PPLogger
from lib.Parser.Klarf18 import Klarf18

LOG_ARGS = ['--logfile', '--log_file', '--log']
DEFAULT_YAML_FILE = '/export/home/dpower/project/scripts/py/resources/JND_CONFIG.yaml'
DEFAULT_LOG_DIR = '/export/home/dpower/project/log'

def initialize_log_file():
    """Initialize the log file based on script name and environment variable."""
    script_name = os.path.basename(sys.argv[0])
    log_file_name = os.path.splitext(script_name)[0] + '.log'
    log_dir = os.environ.get('DPLOG', DEFAULT_LOG_DIR)
    log_file = os.path.join(log_dir, log_file_name)

    for i, arg in enumerate(sys.argv):
        for log_arg in LOG_ARGS:
            if arg.startswith(log_arg):
                if '=' in arg:
                    log_file = arg.split('=')[1]
                else:
                    log_file_index = i + 1
                    if log_file_index < len(sys.argv):
                        log_file = sys.argv[log_file_index]
                    else:
                        log_file = sys.argv[log_file_index - 1]
                break
    return log_file

def get_base_filename(input_file):
    """Extract base filename."""
    return os.path.splitext(os.path.basename(input_file))[0]

def get_tpno_from_klarf_body(content):
    """Extract TPNO from DeviceID field in Klarf 1.8 content.
    
    Looks for patterns like:
        Field DeviceID 1 {"FN43"}
        DeviceID 1 {"FN43"}
    """
    match = re.search(r'DeviceID\s+\d+\s*\{\s*"([^"]+)"\s*\}', content, re.IGNORECASE)
    if match:
        device_id = match.group(1).strip()
        if device_id and device_id.isalnum() and len(device_id) >= 2:
            return device_id
    return None

def get_tpno_from_filename(base_filename):
    """Determine TPNO based on base filename and validate it (last resort fallback)."""
    if base_filename.startswith("7G"):
        tpno_candidate = base_filename[2:7]
        if tpno_candidate.isalnum() and len(tpno_candidate) >= 4:
            return tpno_candidate
        else:
            return None
    
    parts = base_filename.split('_')
    if len(parts) > 1:
        tpno_candidate = parts[1]
        if tpno_candidate.isalnum() and len(tpno_candidate) > 1:
            return tpno_candidate
        else:
            return None
    
    tpno_candidate = base_filename[2:7]
    if tpno_candidate.isalnum() and len(tpno_candidate) > 1:
        return tpno_candidate
    return None

def find_in_dict(d, key):
    """Recursively find a key in a nested dictionary structure."""
    if not isinstance(d, dict):
        return None
    if key in d:
        return d[key]
    for k, v in d.items():
        if k.startswith("_"):
            continue
        if isinstance(v, dict):
            res = find_in_dict(v, key)
            if res is not None:
                return res
        elif isinstance(v, list):
            for item in v:
                if isinstance(item, dict):
                    res = find_in_dict(item, key)
                    if res is not None:
                        return res
    return None

def get_klarf_die_stats(content):
    """Extract tested die range (minX, maxX, minY, maxY) from Klarf content."""
    min_x, min_y, max_x, max_y = 99999, 99999, -99999, -99999
    dies = set()
    
    # 1. Try to find SampleTestPlanList
    match = re.search(r'SampleTestPlanList\s*\{\s*Columns\s+2\s*\{[^}]*\}\s*Data\s+\d+\s*\{([^}]+)\}', content, re.DOTALL | re.IGNORECASE)
    if match:
        data_block = match.group(1)
        coords = re.findall(r'(-?\d+)\s+(-?\d+)', data_block)
        for x_str, y_str in coords:
            x, y = int(x_str), int(y_str)
            dies.add((x, y))
    else:
        # 2. Try SampleTestPlan (Klarf 1.2 style or fallback)
        match = re.search(r'SampleTestPlan\s+\d+\s+([^;]+);', content, re.DOTALL | re.IGNORECASE)
        if match:
            data_block = match.group(1)
            coords = re.findall(r'(-?\d+)\s+(-?\d+)', data_block)
            for x_str, y_str in coords:
                x, y = int(x_str), int(y_str)
                dies.add((x, y))
                
    if not dies:
        # 3. Fall back to DefectList coordinates
        defect_match = re.search(r'DefectList\s*\{\s*Columns\s+\d+\s*\{([^}]+)\}\s*Data\s+\d+\s*\{([^}]+)\}', content, re.DOTALL | re.IGNORECASE)
        if defect_match:
            cols_str, data_str = defect_match.group(1), defect_match.group(2)
            # Find XINDEX and YINDEX columns index
            cols = [c.strip().split()[-1].upper() for c in cols_str.split(',')]
            if 'XINDEX' in cols and 'YINDEX' in cols:
                x_idx = cols.index('XINDEX')
                y_idx = cols.index('YINDEX')
                rows = data_str.replace(';', '\n').split('\n')
                for row in rows:
                    row = row.strip()
                    if not row:
                        continue
                    parts = row.split()
                    if len(parts) > max(x_idx, y_idx):
                        try:
                            x = int(parts[x_idx])
                            y = int(parts[y_idx])
                            dies.add((x, y))
                        except ValueError:
                            pass
    if dies:
        xs = [d[0] for d in dies]
        ys = [d[1] for d in dies]
        min_x = min(xs)
        max_x = max(xs)
        min_y = min(ys)
        max_y = max(ys)
        columns = max_x - min_x + 1
        rows = max_y - min_y + 1
        Log.INFO(f"Klarf die range bounds calculated: minX={min_x}, maxX={max_x}, minY={min_y}, maxY={max_y}")
        return {
            "minX": min_x,
            "minY": min_y,
            "maxX": max_x,
            "maxY": max_y,
            "deviceCount": len(dies),
            "columns": columns,
            "rows": rows,
        }
    return None

def parse_existing_metadata(content):
    """Parse existing metadata attributes and retrieve original Klarf body content."""
    existing_attrs = {}
    metadata_match = re.search(r'<Metadata>\s*(.*?)\s*</Metadata>', content, re.DOTALL | re.IGNORECASE)
    if metadata_match:
        attrs_block = metadata_match.group(1)
        for line in attrs_block.splitlines():
            line = line.strip()
            if not line.startswith('<Attribute'):
                continue
            name_m = re.search(r'Name=["\']([^"\']*)["\']', line, re.IGNORECASE)
            source_m = re.search(r'Source=["\']([^"\']*)["\']', line, re.IGNORECASE)
            value_m = re.search(r'Value=["\']([^"\']*)["\']', line, re.IGNORECASE)
            if name_m and source_m and value_m:
                existing_attrs[name_m.group(1)] = (source_m.group(1), value_m.group(1))
        body = content[metadata_match.end():].lstrip()
        return existing_attrs, body
    return {}, content

def main():
    dp_exit = Util.dp_exit
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    
    # Process CLI arguments
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    if params.get('pplog'):
        pplogger.set_to_be_logged(True)
        
    if len(sys.argv) < 2 or 'infile' not in params:
        Log.INFO("No input file specified!")
        dp_exit(1, pplogger=pplogger, error="No input file specified!")
        
    input_file = params['infile']
    outbox = params['out']
    
    yaml_file = params.get('config_file', DEFAULT_YAML_FILE)
    yaml_data = Util.load_yaml(yaml_file)
    fjm_location = yaml_data['Klarf18']['fjm_location']
    
    site = "JND"
    pplogger.set_raw_file(input_file)
    pplogger.set_env("jnd_klarf_18_wmc_enricher")
    pplogger.set_site(site)
    pplogger.set_script(os.path.basename(__file__))
    
    # Configure writer
    base_file = os.path.basename(input_file)
    fname, fext = os.path.splitext(base_file)
    if fext == '.gz':
        fname, fext = os.path.splitext(fname)
        fext = fext.lstrip(".") + '.gz'
    else:
        fext = fext.lstrip(".")
    
    writer_kwargs = {
        'outdir': outbox,
        'basename': fname,
        'ext': fext,
        'gzipIFF': True,
        'pplogger': pplogger
    }
    writer_instance = Writer(**writer_kwargs)
    
    # Read original content
    try:
        if input_file.endswith('.gz'):
            with gzip.open(input_file, 'rt', encoding='utf-8', errors='ignore') as f:
                original_content = f.read()
        else:
            with open(input_file, 'r', encoding='utf-8', errors='ignore') as f:
                original_content = f.read()
    except Exception as e:
        Log.ERROR(f"Failed to read input file: {e}")
        dp_exit(1, pplogger=pplogger, error=f"Failed to read input file: {e}")
        
    # Parse existing metadata
    existing_attrs, original_klarf_body = parse_existing_metadata(original_content)
    Log.INFO(f"Parsed {len(existing_attrs)} existing metadata attributes from the file.")
    
    # Retrieve raw lot and wafer number
    raw_lot = "NA"
    raw_wafer_number = "NA"
    
    if 'LotId' in existing_attrs:
        raw_lot = existing_attrs['LotId'][1]
    
    if 'WaferNumber' in existing_attrs:
        raw_wafer_number = existing_attrs['WaferNumber'][1]
    elif 'Slot' in existing_attrs:
        raw_wafer_number = existing_attrs['Slot'][1]
        
    # Fallback to parsing from Klarf using Klarf18
    if raw_lot == "NA" or raw_wafer_number == "NA":
        try:
            klarf_parser = Klarf18()
            metadata = klarf_parser.parse(input_file)
            
            if raw_lot == "NA":
                lr = find_in_dict(metadata, "LotRecord")
                raw_lot_val = lr.get("_val", "NA") if isinstance(lr, dict) else (lr if lr else "NA")
                if raw_lot_val != "NA":
                    raw_lot = raw_lot_val
                    
            if raw_wafer_number == "NA":
                wr = find_in_dict(metadata, "WaferRecord")
                raw_wafer_val = wr.get("_val", "NA") if isinstance(wr, dict) else (wr if wr else "NA")
                
                slot_val = find_in_dict(metadata, "SlotNumber")
                if isinstance(slot_val, list) and len(slot_val) > 0:
                    raw_wafer_number = slot_val[0]
                elif raw_wafer_val != "NA":
                    raw_wafer_number = re.sub(r'\D', '', str(raw_wafer_val))
        except Exception as e:
            Log.WARN(f"Failed to parse Klarf structure for fallback metadata: {e}")
            
    if raw_wafer_number != "NA":
        raw_wafer_number = Util.format_wafer_number(raw_wafer_number)
        
    pplogger.set_lot(raw_lot)
    pplogger.set_waf_num(raw_wafer_number)
    
    # Retrieve TPNO to locate FJM
    # Priority 1: DeviceID field from Klarf body (most direct source)
    tpno = get_tpno_from_klarf_body(original_content)
    if tpno:
        Log.INFO(f"TPNO={tpno} extracted from Klarf DeviceID field (primary)")
    
    # Priority 2: Product/AlternateProduct metadata attribute (2nd dash-segment, e.g. WA0034-FN43-... -> FN43)
    if not tpno:
        for attr_key in ['Product', 'AlternateProduct']:
            if attr_key in existing_attrs:
                attr_val = existing_attrs[attr_key][1]
                parts = attr_val.split('-')
                if len(parts) > 1 and parts[1].isalnum() and len(parts[1]) >= 2:
                    tpno = parts[1]
                    Log.INFO(f"TPNO={tpno} extracted from existing {attr_key} metadata attribute (fallback 1)")
                    break
    
    # Priority 3: Filename-based extraction (last resort)
    if not tpno:
        base_filename = get_base_filename(input_file)
        tpno = get_tpno_from_filename(base_filename)
        if tpno:
            Log.INFO(f"TPNO={tpno} extracted from filename (fallback 2)")
        else:
            tpno = "Invalid TPNO"
            Log.WARN(f"Could not extract valid TPNO from any source")
                
    fjm = None
    if tpno.isalnum() and len(tpno) >= 4 and tpno != "Invalid TPNO":
        fjm = JndUtil.find_first_jnd_fjm_file(fjm_location, tpno)
        Log.INFO(f"FJM={fjm} || TPNO={tpno}")
    else:
        Log.WARN(f"TPNO={tpno} extracted is not valid, cant get fjm file and cant enrich with wmc.")
        writer_instance.noMeta = True
        
    # Get wafer coordinates and bounds from Klarf body
    stats = get_klarf_die_stats(original_content)
    if not stats:
        Log.WARN("Could not extract wafer map statistics from Klarf file.")
        writer_instance.noWMap = True
        stats = {
            "minX": 0, "minY": 0, "maxX": 0, "maxY": 0,
            "deviceCount": 0, "columns": 0, "rows": 0
        }
        
    wmap = Wmap(stats)
    wmap.wf_units = yaml_data['Klarf18']['WmcWaferUnits']
    wmap.flat = yaml_data['Klarf18']['WmcWaferFlat']
    wmap.flat_type = yaml_data['Klarf18']['WmcFlatType']
    wmap.positive_x = yaml_data['Klarf18']['WmcPositiveX']
    wmap.positive_y = yaml_data['Klarf18']['WmcPositiveY']
    
    # Parse FJM and get WMC details
    wmc_dictionary = {}
    if fjm and not writer_instance.noWMap:
        try:
            Log.INFO(f"Try to enrich wmc from FJM file={fjm}")
            fjm_wmc_generator = FJMParser(fjm, wmap)
            wmc_dictionary = fjm_wmc_generator.get_wmc_in_dictionary()
            wmc_dictionary['maskSet'] = fjm_wmc_generator.get_mask_info()
        except Exception as e:
            Log.ERROR(f"Error occurred during WMC/FJM enrichment: {e}", exc_info=True)
            writer_instance.noWMap = True
            wmc_dictionary = {}
    else:
        if not fjm:
            Log.WARN(f"FJM file = {fjm} is not found")
        writer_instance.noWMap = True
        wmc_dictionary = {}
        
    center_x = wmc_dictionary.get('center_x', None)
    center_y = wmc_dictionary.get('center_y', None)
    if center_x is None or center_y is None:
        writer_instance.noWMap = True
        
    # Populate MetadataDTO and compile the prepended block
    source_mapping = yaml_data['Klarf18']['source_mapping']
    field_mapping = yaml_data['Klarf18']['field_mapping']
    
    # 1. Add existing attributes
    metadataDTO_instance = MetadataDTO(field_mapping={}, source_mapping=source_mapping)
    for name, (source, value) in existing_attrs.items():
        dto_attr_name = getattr(MetadataDTO, name, name)
        metadataDTO_instance.set_metadata_self_attribute(dto_attr_name, source=source, value=value)
        
    # 2. Filter field_mapping to prevent overwriting existing attributes
    filtered_wmc_mapping = {}
    if 'wmc' in field_mapping:
        for key, value in field_mapping['wmc'].items():
            resolved_attr_name = getattr(MetadataDTO, value, value)
            if resolved_attr_name not in existing_attrs:
                filtered_wmc_mapping[key] = value
            else:
                Log.INFO(f"Skipping WMC mapping for '{key}' -> '{resolved_attr_name}' because it already exists in metadata.")
                
    metadataDTO_instance.field_mapping = {'wmc': filtered_wmc_mapping}
    
    # 3. Compile prepended block
    wmc_data = {'wmc': wmc_dictionary} if (wmc_dictionary and not writer_instance.noWMap) else {}
    metadata = metadataDTO_instance.generate_metadata_xml(data=wmc_data)
    enriched_content = metadata + "\n" + original_klarf_body
    
    # Write enriched file
    try:
        writer_instance.open()
        writer_instance.put(enriched_content)
        writer_instance.close()
        Log.INFO(f"Enriched file written successfully to: {writer_instance.openedfile}")
    except Exception as e:
        Log.ERROR(f"Failed to write output: {e}")
        dp_exit(1, pplogger=pplogger, error=str(e))
        
    dp_exit(0, pplogger=pplogger)

if __name__ == '__main__':
    main()
