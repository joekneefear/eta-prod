#!/usr/bin/env python3
"""
SYNOPSIS
    fcs_eagle_log_sxml.py <input file>
        --site <site_code>
        --loc <location>
        --facilityfile <facilityMapping.ini>
        --out <output dir>
        [--config <cfg_tester_type>]
        [--finallot] [--rellot] [--logfile <path>] [--nolookup]
        [--ws_source prod|qa] [--config_file <xFCS_FACILITY_MAPPING.yaml>]
        [--force_prd] [--debug] [--trace] [--metastrip] [--pplog] [--fork <dir>] [--qde] [-V]

DESCRIPTION
    Read Eagle log files and generate SXML output (STDF XML format).

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2026-May-21 - initial Python SXML translator from fcs_eagle_log_IFF.pl
    2026-May-21 - ERT onLotProd metadata population via RefdbAPIClient
    2026-May-21 - SXML formatter aligned to production STDML structure

LICENSE
    (C) onsemi 2026 All rights reserved.
"""

import os
import sys
import gzip
import zipfile
import configparser
from os.path import basename, dirname

from lib.Log import Log
from lib.Util import Util
from lib.Writer import Writer
from lib.Formatter.SXML import SXML
from lib.Formatter.EagleSxml import EagleSxml
from lib.Parser.EagleParser import EagleParser
from lib.Processor.EagleSiteProcessor import EagleSiteProcessor, VALID_SITES
from lib.PPLogger import PPLogger
from lib.Utility.EagleMetadataPopulator import (
    EagleMetadataPopulator,
    create_from_config,
    resolve_ert_base_url,
)

VERSION = "1.0"
TESTER = "EAGLE"


def initialize_log_file():
    script_name = os.path.basename(sys.argv[0])
    log_file_name = os.path.splitext(script_name)[0] + ".log"
    log_dir = os.environ.get("DPLOG", "/export/home/dpower/project/log")
    log_file = os.path.join(log_dir, log_file_name)
    for i, arg in enumerate(sys.argv):
        if arg.startswith("--logfile") or arg.startswith("--log_file") or arg == "--log":
            if "=" in arg:
                log_file = arg.split("=", 1)[1]
            elif i + 1 < len(sys.argv):
                log_file = sys.argv[i + 1]
            break
    return log_file


def decompress_input(infile):
    output = infile
    if infile.endswith(".gz"):
        output = infile[:-3]
        with gzip.open(infile, "rb") as f_in, open(output, "wb") as f_out:
            f_out.write(f_in.read())
        Log.INFO(f"gunzipped file = {output}")
    elif infile.endswith(".zip"):
        output = infile[:-4]
        with zipfile.ZipFile(infile, "r") as zf:
            names = [n for n in zf.namelist() if not n.endswith("/")]
            if not names:
                Util.dp_exit(1, f"zip archive empty: {infile}")
            with zf.open(names[0]) as src, open(output, "wb") as dst:
                dst.write(src.read())
        Log.INFO(f"unzipped file = {output}")
    return output


def load_facility(facility_file, location, finallot, site):
    config = configparser.ConfigParser()
    config.read(facility_file)
    if location not in config:
        Util.dp_exit(1, f"location {location} not in facility file")
    section = config[location]
    if finallot:
        facility = section.get("finalTest", section.get("finaltest", "NA"))
        if site == "meft":
            facility = section.get("probe", facility)
    else:
        facility = section.get("probe", "NA")
    if finallot:
        ert_url = section.get("ppLotProd", section.get("pplotprod", ""))
    else:
        ert_url = section.get("onLotProd", section.get("onlotprod", ""))
    return facility, ert_url


def main():
    dp_exit = Util.dp_exit
    log_file = initialize_log_file()
    pplogger = PPLogger()
    pplogger.set_to_be_logged(False)
    Log.configure_logger(log_file=log_file, pplogger=pplogger)

    if len(sys.argv) < 2:
        Util.dp_exit(1, "usage: fcs_eagle_log_sxml.py <input> --out DIR --site SITE --loc LOC --facilityfile FILE")

    arguments = sys.argv[1:]
    params = Util.process_command_line_args(list(arguments))

    if params.get("V"):
        print(VERSION)
        dp_exit(0)

    for req in ("out", "site", "loc", "facilityfile"):
        if req not in params:
            Util.dp_exit(1, f"--{req} is required")

    site = params["site"]
    if site not in VALID_SITES:
        Util.dp_exit(1, f"wrong site code : {site}")

    if params.get("pplog"):
        pplogger.set_to_be_logged(True)

    infile = params["infile"]
    if not os.path.isfile(infile):
        Util.dp_exit(1, f"input file does not exist {infile}")

    pplogger.set_raw_file(infile)
    pplogger.set_env(site, "eagle")

    finallot = bool(params.get("finallot"))
    rellot = bool(params.get("rellot"))
    facility, ert_url = load_facility(params["facilityfile"], params["loc"], finallot, site)
    config_file = params.get(
        "config_file",
        os.path.join(dirname(os.path.abspath(__file__)), "resources", "xFCS_FACILITY_MAPPING.yaml"),
    )
    config_data = Util.load_yaml(config_file) if os.path.isfile(config_file) else {}
    ert_url = resolve_ert_base_url(ert_url, params["loc"], config_data) or ert_url
    Log.INFO(f"Site code = {site}")
    Log.INFO(f"FACILITY|EQUIP6_ID={facility}")
    if ert_url:
        Log.INFO(f"ERT URL={ert_url}")

    output = decompress_input(infile)
    parser = EagleParser()
    model, sbox_flg = parser.read_file(output, site)

    if sbox_flg:
        Log.WARN("Parser flagged sandbox")

    header = model.header
    header.VERSION = VERSION
    header.isFinalLot = finallot
    header.isRelLot = rellot
    header.EQUIP6_ID = facility
    header.ertUrl = ert_url

    writer = Writer(
        outdir=params["out"],
        forkdir=params.get("fork"),
        qde=params.get("qde"),
        basename=basename(output),
        ext="sxml",
        gzipIFF=params.get("gzip", True),
        pplogger=pplogger,
        site=site,
        script_name=os.path.basename(__file__),
    )
    if sbox_flg:
        writer.forced_sandbox = True

    processor = EagleSiteProcessor(model, writer, parser, site, infile, params)
    if model.misc.get("err_msg"):
        Util.dp_exit(1, model.misc["err_msg"])

    processor.apply_site_rules()
    processor.apply_program_rules(params.get("config"), dirname(dirname(os.path.abspath(__file__))))

    ws_source = params.get("ws_source", "prod")
    metadata_populator = create_from_config(config_data, ws_source) if config_data else EagleMetadataPopulator()
    lookup_options = {
        "nolookup": params.get("nolookup"),
        "metastrip": params.get("metastrip"),
        "site": site,
        "loc": params["loc"],
        "force_prd": params.get("force_prd"),
        "ert_url": ert_url,
    }
    metadata_populator.populate_header(header, writer=writer, options=lookup_options, infile=infile)

    processor.validate_results(is_rellot=rellot)

    if not finallot and not rellot:
        try:
            model.updateWMap()
        except Exception as exc:
            Log.WARN(f"WMAP update skipped: {exc}")
        if getattr(header, "SOURCE_LOT", "") and model.wafers:
            w = model.wafers[0]
            w.name = f"{header.SOURCE_LOT}_{int(w.number or 0):02d}"

    if finallot or rellot:
        model.updateProgram()
    else:
        model.updateProgram("MAP_PGM")

    pplogger.set_model_header(model)

    sxml_builder = EagleSxml(model=model, input_filename=basename(infile))
    xml_lines = sxml_builder.build_xml_lines(site=site)
    sxml_writer = SXML(writer=writer, sxml=xml_lines)
    sxml_writer.write_list_of_line_string_to_file()

    if infile.endswith(".gz") and os.path.isfile(output):
        os.remove(output)
    if infile.endswith(".zip") and os.path.isfile(output):
        os.remove(output)

    dp_exit(0, pplogger=pplogger)


if __name__ == "__main__":
    main()
