#!/usr/bin/env python3.12

"""
SYNOPSIS
    INNO Final Test (FT) XLSX Parser and Enricher

DESCRIPTION
    This script reads an INNO FT Excel (.xlsx) file, parses its metadata,
    enriches it with RefDB data, and generates a new IFF output file.
    Supports site-specific enrichment logic via YAML configuration and
    database logging via PPLogger.

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-Jul-02 - Initial implementation

LICENSE
    (C) onsemi 2026 All rights reserved.
"""

import os
import sys
import gzip
import yaml
from lib.Log import Log
from lib.Util import Util
from lib.Parser.InnoFtXlsxSts8200Parser import InnoFtXlsxSts8200Parser
from lib.Config.InnoFtXlsxSts8200ParserConfig import InnoFtXlsxSts8200ParserConfig
from lib.Enricher.InnoFtXlsxSts8200Enricher import InnoFtXlsxSts8200Enricher
from lib.Formatter.IFF import IFF
from lib.Writer import Writer
from lib.PPLogger import PPLogger
from lib.WS.RefdbAPIClient import RefdbAPIClient


def initialize_log_file():
    """
    Initialize log file path from environment or CLI arguments.
    
    Respects:
    - DPLOG environment variable (default: /export/home/dpower/project/log)
    - --logfile, --log_file, --log CLI arguments
    
    Returns:
        str: Full path to log file
    """
    script_name = os.path.basename(sys.argv[0])
    log_file_name = os.path.splitext(script_name)[0] + '.log'

    log_dir = os.environ.get('DPLOG', '/export/home/dpower/project/log')
    log_file = os.path.join(log_dir, log_file_name)

    log_args = ['--logfile', '--log_file', '--log']
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
    """
    Main entry point: orchestrate parsing, enrichment, and IFF output.
    
    Flow:
    1. Setup logging and PPLogger
    2. Parse CLI arguments
    3. Load YAML enrichment configuration
    4. Decompress .gz if needed
    5. Determine site (--site CLI takes priority, DEFAULT is fallback)
    6. Load parser configuration (site-specific field mappings)
    7. Parse XLSX file into Model (with site-specific configuration)
    8. Set lot in PPLogger
    9. Set PPLogger Environment from Config
    10. Fetch RefDB metadata if configured
    11. Enrich model with metadata
    12. Build limits and write IFF output
    13. Exit cleanly
    """

    def _as_bool(value):
        """Convert value to boolean."""
        if isinstance(value, bool):
            return value
        if value is None:
            return False
        if isinstance(value, str):
            return value.strip().lower() in {'1', 'true', 'yes', 'y', 'on'}
        return bool(value)

    # Initialize logging
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)

    if len(sys.argv) < 2:
        Log.INFO("No input file specified!!!")
        Util.dp_exit(1, pplogger=pplogger, error="No input file specified!!!")

    # Parse CLI arguments
    arguments = sys.argv[1:]
    params = Util.process_command_line_args(arguments)

    Log.INFO(f"Raw Arguments: {' '.join(sys.argv)}")
    Log.INFO(f"Parsed Parameters: {params}")

    input_file = params.get('infile')
    out_dir = params.get('out')
    config_file = params.get('config', os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 
        'resources', 'InnoFtXlsxSts8200_Enrichment_config.yaml'))
    site_arg = params.get('site')
    forced_final_folder = params.get('forced_final_folder')
    force_prd = _as_bool(params.get('force_prd'))
    ws_url_config = params.get('ws_url')
    ws_source = params.get('ws_source')

    # Enable PPLOG if requested via CLI
    if params.get('pplog'):
        pplogger.set_to_be_logged(True)
        Log.INFO("PPLOG database persistence enabled")

    # Validate required arguments
    if not input_file:
        Log.ERROR("Error: --infile is required")
        Util.dp_exit(1, pplogger=pplogger, error="Error: --infile is required")
    if not out_dir:
        Log.ERROR("Error: --out is required")
        Util.dp_exit(1, pplogger=pplogger, error="Error: --out is required")

    Log.INFO(f"Starting INNO FT XLSX Enrichment for {input_file}")

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
            Log.ERROR(f"Configuration file {config_file} not found.")
            Util.dp_exit(1, pplogger=pplogger, error=f"Config file not found: {config_file}")
    except Exception as e:
        Log.ERROR(f"Failed to load configuration file {config_file}: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    # 2. Decompress .gz if needed
    working_file = input_file
    if input_file.endswith('.gz'):
        try:
            Log.INFO(f"Decompressing {input_file}")
            with gzip.open(input_file, 'rb') as f_in:
                temp_file = input_file[:-3]  # Remove .gz extension
                with open(temp_file, 'wb') as f_out:
                    f_out.write(f_in.read())
            working_file = temp_file
            Log.INFO(f"Decompressed to {working_file}")
        except Exception as e:
            Log.ERROR(f"Failed to decompress {input_file}: {e}")
            Util.dp_exit(1, pplogger=pplogger, error=str(e))

    # 3. Determine Site (--site CLI takes priority, DEFAULT is fallback)
    site = params.get('site') or "DEFAULT"
    Log.INFO(f"Enrichment site: {site}")

    # 4. Load parser configuration (site-specific rules for field mapping and transformations)
    try:
        parser_config_file = params.get(
            'parser_config',
            os.path.join(
                os.path.dirname(os.path.abspath(__file__)), 
                'resources', 'InnoFtXlsx_ParserConfig.yaml'))
        
        parser_config = InnoFtXlsxSts8200ParserConfig(config_file=parser_config_file, site=site)
        Log.INFO(f"Loaded parser configuration from: {parser_config_file}")
    except Exception as e:
        Log.ERROR(f"Failed to load parser configuration: {e}")
        parser_config = InnoFtXlsxSts8200ParserConfig()  # Fallback to defaults
        Log.INFO("Falling back to default parser configuration")

    # 5. Parse XLSX file into Model (with site-specific configuration)
    try:
        parser = InnoFtXlsxSts8200Parser(config=parser_config, pplogger=pplogger)
        model = parser.parse_to_model(working_file)
        Log.INFO("XLSX parsed successfully")
    except Exception as e:
        Log.ERROR(f"Failed to parse XLSX: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    # 6. Set lot in PPLogger
    pplogger.set_lot(model.header.LOT)

    # 7. Set PPLogger Environment from Config
    site_config = config.get(site, config.get("DEFAULT", {}))
    env_name = site_config.get("env", "inno_ft_xlsx_sts8200")
    pplogger.set_env(env_name)
    pplogger.set_site(site)
    Log.DEBUG(f"PPLOG Environment: {env_name}")

    # 8. Fetch RefDB metadata if configured
    def _is_no_data_status(status_value):
        """Check if status indicates no data or error."""
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

    lot_id = model.header.LOT
    if lot_id != "NA" and ws_url_config and ws_source:
        try:
            Log.INFO(f"Fetching Reference DB metadata for lot {lot_id} using source {ws_source}")
            ws_url_ref_data = Util.load_yaml(ws_url_config)
            ws_urls = Util.configure_ws_urls(ws_source, ws_url_ref_data)

            refdb_api_client = RefdbAPIClient()

            def fetch_lot_metadata(base_url, lot, site_param=None):
                """Fetch lot metadata from RefDB endpoint."""
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

            Log.INFO(f"Attempting RefDB WS: {on_lot_url} for lot {lot_id}")
            on_lot_called = True
            lot_metadata_raw = fetch_lot_metadata(on_lot_url, lot_id)

            if isinstance(lot_metadata_raw, dict):
                Log.DEBUG(f"Raw Reference DB Response: {lot_metadata_raw}")
                on_lot_status = lot_metadata_raw.get('status')
                on_lot_no_data_status = _is_no_data_status(on_lot_status)

                if on_lot_no_data_status:
                    Log.WARN(f"Reference DB response status indicates no data/error: status={on_lot_status}")

                    # Retry with ws_site_retry if configured
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
            Log.WARN(f"Failed to fetch RefDB metadata: {e}. Fallback logic in Enricher will be used.")

    # 10. Enrich model with metadata
    try:
        enricher = InnoFtXlsxSts8200Enricher(
            raw_header=model.header._raw,
            model=model,
            config=config,
            site=site,
            lot_metadata=lot_metadata
        )
        model = enricher.enrich()
        Log.INFO("Model enriched successfully")
    except Exception as e:
        Log.ERROR(f"Failed to enrich model: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    # 9. Determine sandbox routing based on RefDB availability
    def _mapping_uses_refdb(default_cfg, selected_site_cfg):
        """Check if any field in mapping uses 'refdb' type."""
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

    # 11. Set additional model metadata
    model.header.DATA_FILE_NAME = os.path.basename(input_file)
    model.header.AREA = "FT"
    model.header.PROGRAM_CLASS = 2
    
    # Set START_TIME and END_TIME on wafer from header (required for print_par grouping)
    if model.wafers:
        for wafer in model.wafers:
            wafer.START_TIME = model.header.START_TIME if hasattr(model.header, 'START_TIME') else None
            wafer.END_TIME = model.header.END_TIME if hasattr(model.header, 'END_TIME') else None

    Log.DEBUG(f"Set AREA=FT, PROGRAM_CLASS=2")

    # 12. Build limits and prepare output
    model.build_limit()

    # 13. Write IFF output
    try:
        base_file = os.path.basename(working_file)
        fname, fext = os.path.splitext(base_file)
        if fext == '.gz':
            fname, fext = os.path.splitext(fname)
            fext = 'xlsx.iff.gz'
        else:
            fext = 'xlsx.iff'

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

        # Instantiate IFF formatter and write data
        iff_args = {
            'writer': writer,
            'model': model
        }
        iff = IFF(iff_args)
        iff.data_items = ['site', 'partid', 'touchdown_num', 'ecid', 'hard_bin', 'soft_bin', 'bindesc']
        iff.test_items = ['number', 'name', 'units']
        iff.bin_items = ['number', 'name', 'PF', 'count']
        iff.print_par()
        iff.print_limit()

        pplogger.set_limit_file(model.limit.limit_file)
        Log.INFO(f"IFF output written successfully")

    except Exception as e:
        Log.ERROR(f"Failed to write IFF output: {e}")
        Util.dp_exit(1, pplogger=pplogger, error=str(e))

    Log.INFO("INNO FT XLSX Enrichment completed successfully")
    Util.dp_exit(0, pplogger=pplogger)


if __name__ == '__main__':
    main()
