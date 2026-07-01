#!/usr/bin/env python3.12

"""
SYNOPSIS
    Klarf 1.8 Parser and Enricher

DESCRIPTION
    This script reads a Klarf 1.8 file, parses its metadata, and generates a new
    file with a <Metadata> section at the top. Supports site-specific enrichment
    logic via YAML configuration and database logging via PPLogger.

AUTHOR
    jgarcia

CHANGES
    2026-Feb-16 - initial
    2026-Feb-16 - added YAML config and site-awareness
    2026-Feb-16 - added PPLogger for refdb.pp_log persistence
"""

import os
import sys
import gzip
import yaml
from lib.Log import Log
from lib.Util import Util
from lib.Parser.Klarf18 import Klarf18
from lib.Enricher.Klarf18Enricher import Klarf18Enricher
from lib.Writer import Writer
from lib.PPLogger import PPLogger
from lib.WS.RefdbAPIClient import RefdbAPIClient

def initialize_log_file():
    script_name = os.path.basename(sys.argv[0])  # get the script filename
    log_file_name = os.path.splitext(script_name)[0] + '.log'  # remove extension and add .log

    log_dir = os.environ.get('DPLOG', '/export/home/dpower/project/log')  # get DPLOG environment variable, with a default
    log_file = os.path.join(log_dir, log_file_name)  # join directory and filename

    log_args = ['--logfile', '--log_file', '--log']  # list of possible log file arguments
    for i, arg in enumerate(sys.argv):
        for log_arg in log_args:
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

def main():
    def _as_bool(value):
        if isinstance(value, bool):
            return value
        if value is None:
            return False
        if isinstance(value, str):
            return value.strip().lower() in {'1', 'true', 'yes', 'y', 'on'}
        return bool(value)

    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)
    
    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        Util.dp_exit(1, pplogger=pplogger, error="No input file specified!!!")
    
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)
    
    Log.INFO(f"Raw Arguments: {' '.join(sys.argv)}")
    Log.INFO(f"Parsed Parameters: {params}")
    
    input_file = params.get('infile')
    out_dir = params.get('out')
    config_file = params.get('config', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'resources', 'Klarf18_Enrichment.yaml'))
    site_arg = params.get('site')
    forced_final_folder = params.get('forced_final_folder')
    force_prd = _as_bool(params.get('force_prd'))
    ws_url_config = params.get('ws_url')
    ws_source = params.get('ws_source')
    
    # Enable PPLOG if requested via CLI
    if params.get('pplog'):
        pplogger.set_to_be_logged(True)
        Log.INFO("PPLOG database persistence enabled")

    if not input_file:
        Log.ERROR("Error: --infile is required")
        Util.dp_exit(1, pplogger=pplogger, error="Error: --infile is required")
    if not out_dir:
        Log.ERROR("Error: --out is required")
        Util.dp_exit(1, pplogger=pplogger, error="Error: --out is required")

    Log.INFO(f"Starting Klarf 1.8 Enrichment for {input_file}")

    # Set up PPLogger metadata
    pplogger.set_raw_file(input_file)
    pplogger.set_script(os.path.basename(__file__))

    # 1. Load YAML Configuration
    try:
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            Log.INFO(f"Loaded configuration from {config_file}")
        else:
            Log.ERROR(f"Configuration file {config_file} not found. Using inline DEFAULT fallback.")
            config = {
                'DEFAULT': {
                    'env': 'klarf_18_enricher',
                    'fields': {
                        'AlternateProduct': {'type': 'constant', 'value': 'NA'},
                        'Fab': {'type': 'field', 'source': 'FabID', 'index': 0},
                        'Facility': {'type': 'field', 'source': 'FabID', 'index': 0},
                        'LotId': {'type': 'record', 'source': 'LotRecord'},
                        'LotType': {'type': 'constant', 'value': 'NA'},
                        'Process': {'type': 'field', 'source': 'SampleSize', 'index': 0, 'slice': [0, 3]},
                        'Product': {'type': 'field', 'source': 'DeviceID', 'index': 0},
                        'ProbeProgramName': {'type': 'field', 'source': 'DeviceID', 'index': 0},
                        'Recipe': {'type': 'field', 'source': 'RecipeID', 'index': 0},
                        'ResultTime': {'type': 'field', 'source': 'FileTimestamp', 'format': '{0} {1}', 'regex_replace': [r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', r'\3/\1/\2']},
                        'Slot': {'type': 'field', 'source': 'SlotNumber', 'index': 0},
                        'SourceLot': {'type': 'record', 'source': 'LotRecord'},
                        'StartTime': {'type': 'field', 'source': 'ResultTimestamp', 'format': '{0} {1}', 'regex_replace': [r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', r'\3/\1/\2']},
                        'Step': {'type': 'field', 'source': 'StepID', 'index': 0},
                        'Technology': {'type': 'constant', 'value': 'NA'},
                        'TesterId': {'type': 'field', 'source': 'InspectionStationID', 'index': 2},
                        'TesterType': {'type': 'field', 'source': 'InspectionStationID', 'index': 1},
                        'WaferId': {'type': 'wafer_record', 'source': 'WaferRecord', 'source_lot_source': 'LotRecord'},
                        'WaferNumber': {'type': 'field', 'source': 'SlotNumber', 'index': 0}
                    }
                }
            }
    except Exception as e:
        Log.ERROR(f"Failed to load configuration file {config_file}: {e}. Using inline DEFAULT fallback.")
        config = {
            'DEFAULT': {
                'env': 'klarf_18_enricher',
                'fields': {
                    'AlternateProduct': {'type': 'constant', 'value': 'NA'},
                    'Fab': {'type': 'field', 'source': 'FabID', 'index': 0},
                    'Facility': {'type': 'field', 'source': 'FabID', 'index': 0},
                    'LotId': {'type': 'record', 'source': 'LotRecord'},
                    'LotType': {'type': 'constant', 'value': 'NA'},
                    'Process': {'type': 'field', 'source': 'SampleSize', 'index': 0, 'slice': [0, 3]},
                    'Product': {'type': 'field', 'source': 'DeviceID', 'index': 0},
                    'ProbeProgramName': {'type': 'field', 'source': 'DeviceID', 'index': 0},
                    'Recipe': {'type': 'field', 'source': 'RecipeID', 'index': 0},
                    'ResultTime': {'type': 'field', 'source': 'FileTimestamp', 'format': '{0} {1}', 'regex_replace': [r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', r'\3/\1/\2']},
                    'Slot': {'type': 'field', 'source': 'SlotNumber', 'index': 0},
                    'SourceLot': {'type': 'record', 'source': 'LotRecord'},
                    'StartTime': {'type': 'field', 'source': 'ResultTimestamp', 'format': '{0} {1}', 'regex_replace': [r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', r'\3/\1/\2']},
                    'Step': {'type': 'field', 'source': 'StepID', 'index': 0},
                    'Technology': {'type': 'constant', 'value': 'NA'},
                    'TesterId': {'type': 'field', 'source': 'InspectionStationID', 'index': 2},
                    'TesterType': {'type': 'field', 'source': 'InspectionStationID', 'index': 1},
                    'WaferId': {'type': 'wafer_record', 'source': 'WaferRecord', 'source_lot_source': 'LotRecord'},
                    'WaferNumber': {'type': 'field', 'source': 'SlotNumber', 'index': 0}
                }
            }
        }

    # 2. Read original content
    try:
        if input_file.endswith('.gz'):
            with gzip.open(input_file, 'rt') as f:
                original_content = f.read()
        else:
            with open(input_file, 'r', encoding='utf-8', errors='ignore') as f:
                original_content = f.read()
    except Exception as e:
        Log.ERROR(f"Failed to read input file {input_file}: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    # 3. Parse metadata
    try:
        klarf_parser = Klarf18()
        metadata = klarf_parser.parse(input_file)
        Log.INFO(f"Metadata extracted successfully")
        
        # Update Lot information for PPLogger
        def find_record(m, name):
            if not isinstance(m, dict): return None
            if name in m: return m[name]
            for v in m.values():
                if isinstance(v, dict):
                    res = find_record(v, name)
                    if res: return res
                elif isinstance(v, list):
                    for item in v:
                        res = find_record(item, name)
                        if res: return res
            return None

        lr = find_record(metadata, "LotRecord")
        lot_id = lr.get("_val", "NA") if lr and isinstance(lr, dict) else lr if lr else "NA"
        pplogger.set_lot(lot_id)
        
    except Exception as e:
        Log.ERROR(f"Failed to parse metadata: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    # 4. Determine Site (--site CLI takes priority, FabID auto-detect is fallback)
    site = None
    if site_arg and site_arg is not True:
        # --site explicitly provided with a value — use it directly
        site = site_arg
        Log.INFO(f"Site explicitly set from --site: {site}")
    else:
        # Fallback: auto-detect from FabID in parsed metadata
        Log.INFO("No --site value provided. Attempting auto-detection from FabID.")
        
        def find_fab(d, depth=0):
            if depth > 5: return None
            if not isinstance(d, dict): return None
            
            # Case-insensitive check for FabID key
            for k in d.keys():
                if k.upper() == 'FABID':
                    Log.DEBUG(f"Found FabID in metadata: {d[k]}")
                    return d[k]
            
            for v in d.values():
                if isinstance(v, dict):
                    res = find_fab(v, depth+1)
                    if res: return res
                elif isinstance(v, list) and len(v)>0:
                    for item in v:
                        if isinstance(item, dict):
                            res = find_fab(item, depth+1)
                            if res: return res
            return None
            
        _fab_raw = find_fab(metadata)
        fab_id = "UNKNOWN"
        if _fab_raw:
            if isinstance(_fab_raw, list) and len(_fab_raw) > 0:
                fab_id = str(_fab_raw[0]).upper()
            else:
                fab_id = str(_fab_raw).upper()
            
            Log.DEBUG(f"Extracted FabID for site matching: '{fab_id}'")
            # Loop through YAML sites to find a match
            for site_key, site_data in config.items():
                if site_key == "DEFAULT": continue
                if not isinstance(site_data, dict): continue
                
                match_pats = site_data.get("match_fab", [])
                if not match_pats:
                    Log.DEBUG(f"Site '{site_key}' has no match_fab patterns. Skipping.")
                    continue
                
                Log.DEBUG(f"Checking site '{site_key}' patterns {match_pats} against '{fab_id}'")
                if any(pat.upper() in fab_id for pat in match_pats):
                    site = site_key
                    Log.INFO(f"Site auto-detected from FabID: {site}")
                    break
        
        if not site:
            Log.WARN(f"No site mapping matched for FabID '{fab_id}'. Using DEFAULT.")
    
    if not site:
        site = "DEFAULT"
    
    Log.INFO(f"Enrichment site: {site}")
    
    # 5. Set PPLogger Environment from Config
    site_config = config.get(site, config.get("DEFAULT", {}))
    env_name = site_config.get("env", "klarf_18_enricher")
    pplogger.set_env(env_name)
    pplogger.set_site(site)
    Log.DEBUG(f"PPLOG Environment: {env_name}")

    # 3.5 Fetch ERT API Reference Table Metadata if configured
    def _is_no_data_status(status_value):
        if status_value is None:
            return True
        status_text = str(status_value).strip().upper()
        if not status_text:
            return True
        if status_text in {'NO_DATA', 'ERROR', 'NULL', 'NONE'}:
            return True
        if status_text.startswith('ERROR') or 'NO_DATA' in status_text:
            return True
        return False

    lot_metadata = {}
    on_lot_called = False
    on_lot_no_data_status = False
    on_lot_status = None
    if lot_id != "NA" and ws_url_config and ws_source:
        try:
            Log.INFO(f"Fetching Reference DB metadata for lot {lot_id} using source {ws_source}")
            ws_url_ref_data = Util.load_yaml(ws_url_config)
            ws_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)
            
            refdb_api_client = RefdbAPIClient()
            
            def fetch_lot_metadata(base_url, lot, site_param=None):
                try:
                    url = f"{base_url}/{lot}"
                    if site_param:
                        sep = "&" if "?" in url else "?"
                        url = f"{url}{sep}site={site_param}"
                    
                    data = refdb_api_client.get_metadata(url)
                    Log.INFO(f"Metadata retrieved for lot: {lot}, status: {data.get('status', 'unknown') if isinstance(data, dict) else 'non-dict'}")
                    return data
                except Exception as e:
                    Log.ERROR(f"Error retrieving metadata for lot {lot}: {str(e)}")
                    return None

            on_lot_url = ws_urls.get('onlot')
            
            Log.INFO(f"Attempting ERT WS: {on_lot_url} for lot {lot_id}")
            on_lot_called = True
            lot_metadata_raw = fetch_lot_metadata(on_lot_url, lot_id)
            
            if isinstance(lot_metadata_raw, dict):
                Log.DEBUG(f"Raw Reference DB Response: {lot_metadata_raw}")
                on_lot_status = lot_metadata_raw.get('status')
                on_lot_no_data_status = _is_no_data_status(on_lot_status)

                if on_lot_no_data_status:
                    Log.WARN(f"Reference DB response status indicates no data/error: status={on_lot_status}")
                    
                    # BK_SICA88_Rework Retry Feature: if we have NO_DATA and YAML config specifies a retry site param
                    ws_site_retry = site_config.get('ws_site_retry')
                    if ws_site_retry:
                        Log.INFO(f"Status is {on_lot_status} and ws_site_retry='{ws_site_retry}' is configured. Retrying with site param.")
                        lot_metadata_retry = fetch_lot_metadata(on_lot_url, lot_id, site_param=ws_site_retry)
                        if isinstance(lot_metadata_retry, dict):
                            retry_status = lot_metadata_retry.get('status')
                            if not _is_no_data_status(retry_status):
                                Log.INFO(f"Retry successful with status={retry_status}")
                                lot_metadata_raw = lot_metadata_retry
                                on_lot_status = retry_status
                                on_lot_no_data_status = False
                            else:
                                Log.WARN(f"Retry also returned no data: status={retry_status}")
                        else:
                            Log.WARN("Retry return value is not a dictionary.")

                if not on_lot_no_data_status:
                    lot_metadata = lot_metadata_raw
                    Log.INFO(f"Successfully retrieved Reference DB lot metadata with status={on_lot_status}")
            else:
                on_lot_status = None
                on_lot_no_data_status = True
                Log.WARN("Failed to retrieve Reference DB lot metadata (API returned empty/None or non-dict response).")
                
        except Exception as e:
            on_lot_no_data_status = True
            Log.WARN(f"Failed to fetch ERT API metadata: {e}. Fallback logic in Enricher will be used.")

    Log.DEBUG(f"Config keys available: {list(config.keys())}")

    # 6. Enrich content
    try:
        enricher = Klarf18Enricher(metadata, original_content, config=config, site=site, lot_metadata=lot_metadata)
        enriched_content = enricher.enrich()
        Log.INFO(f"Content enriched successfully")
    except Exception as e:
        Log.ERROR(f"Failed to enrich content: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    def _mapping_uses_refdb(default_cfg, selected_site_cfg):
        merged_fields = {}
        if isinstance(default_cfg, dict):
            merged_fields.update(default_cfg.get('fields', {}))
        if isinstance(selected_site_cfg, dict):
            merged_fields.update(selected_site_cfg.get('fields', {}))

        for rule in merged_fields.values():
            if isinstance(rule, dict) and str(rule.get('type', '')).lower() == 'refdb':
                return True
        return False

    site_uses_refdb = _mapping_uses_refdb(config.get('DEFAULT', {}), site_config)
    route_to_sandbox_no_meta = site_uses_refdb and on_lot_called and on_lot_no_data_status

    if route_to_sandbox_no_meta and force_prd:
        Log.WARN("No return data from on_lot endpoint, but configured to load to production (force_prd=True)")
        route_to_sandbox_no_meta = False

    if route_to_sandbox_no_meta:
        Log.WARN(f"on_lot status='{on_lot_status}' for site '{site}' (mapping uses refdb fields). Routing output to SANDBOX via writer.noMeta=True")
    elif site_uses_refdb and on_lot_called and not on_lot_no_data_status:
        Log.INFO(f"on_lot status='{on_lot_status}' returned metadata for site '{site}'. Keeping default PRODUCTION routing (writer.noMeta=False)")

    # 6. Write output
    try:
        base_file = os.path.basename(input_file)
        fname, fext = os.path.splitext(base_file)
        if fext == '.gz':
            fname, fext = os.path.splitext(fname)
            fext = fext.lstrip(".") + '.gz'
        else:
            fext = fext.lstrip(".")

        wr_kwargs = {
            'outdir': out_dir,
            'basename': fname,
            'ext': fext,
            'gzipIFF': True,
            'noMeta': route_to_sandbox_no_meta,
            'forced_sandbox': forced_final_folder == "SBX",
            'pplogger': pplogger
        }
        
        writer = Writer(**wr_kwargs)
        writer.open()
        writer.put(enriched_content)
        writer.close()

        Log.INFO(f"Enriched file written to {writer.openedfile}")
    except Exception as e:
        Log.ERROR(f"Failed to write output: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    Log.INFO("Klarf 1.8 Enrichment completed successfully")
    Util.dp_exit(0, pplogger=pplogger)

if __name__ == '__main__':
    main()
