"""
Populate Eagle header metadata via ERT Reference Tables web service (onLotProd API).
"""

import os
import re
from os.path import basename

from lib.Log import Log
from lib.Util import Util
from lib.WS.RefdbAPIClient import RefdbAPIClient


class EagleMetadataPopulator:
    """ERT metadata lookup aligned with fcs_eagle_log_IFF.pl lot lookup behavior."""

    def __init__(self, refdb_client=None, default_onlot_prod=None, ws_timeout=5.0):
        self.client = refdb_client or RefdbAPIClient()
        self.default_onlot_prod = default_onlot_prod or {
            "onLot": {"status": "ERROR"},
            "onProd": {"status": "ERROR"},
        }
        self.ws_timeout = ws_timeout

    @staticmethod
    def build_onlotprod_url(base_url, lot_id):
        if not base_url or not lot_id:
            return None
        base = str(base_url).strip()
        if base.endswith("/"):
            return f"{base}{lot_id}"
        if "/bylotid" in base.lower():
            return f"{base}/{lot_id}"
        return f"{base}{lot_id}"

    def fetch_ert_metadata(self, base_url, lot_id):
        url = self.build_onlotprod_url(base_url, lot_id)
        if not url:
            return self.default_onlot_prod
        Log.INFO(f"Attempting ERT WS: {url}")
        return Util.get_on_lot_prod_metadata(
            url, self.client, self.ws_timeout, self.default_onlot_prod
        )

    def populate_header(self, header, writer=None, options=None, infile=None):
        """
        Populate header from ERT. Returns True when metadata was found.
        Sets writer.noMeta when lookup fails (unless force_prd).
        """
        options = options or {}
        if options.get("nolookup"):
            Log.INFO("Skipping metadata lookup (--nolookup)")
            return True

        base_url = getattr(header, "ertUrl", None) or options.get("ert_url")
        if not base_url:
            Log.WARN("No ERT onLotProd URL configured; cannot populate metadata")
            if writer and not options.get("force_prd"):
                writer.noMeta = True
            return False

        orig_lot = header.LOT
        site = options.get("site", "")
        loc = options.get("loc", "")
        metastrip = options.get("metastrip")

        found = self._try_populate(header, base_url)

        if not found and loc == "BK" and site == "bksort" and metastrip:
            found = self._bksort_retry_lookup(header, base_url, orig_lot)

        if not found and loc == "UTAC_TH" and site == "utac_th_ft" and metastrip and infile:
            found = self._utac_filename_retry(header, base_url, infile)

        header.LOT = orig_lot

        if not found:
            if writer and not options.get("force_prd"):
                writer.noMeta = True
            Log.WARN(f"Meta NOT found for LOT={orig_lot}")
            return False

        header.SOURCE_LOT = Util.formatSourceLot(getattr(header, "SOURCE_LOT", None), header.LOT)
        Log.INFO(f"Meta found for LOT={header.LOT} SOURCE_LOT={header.SOURCE_LOT}")
        return True

    def _try_populate(self, header, base_url):
        metadata = self.fetch_ert_metadata(base_url, header.LOT)
        return header.populate_metadata_ert(metadata)

    def _bksort_retry_lookup(self, header, base_url, orig_lot):
        temp_lot = orig_lot
        if re.match(r"^M0[a-zA-Z]", temp_lot, re.I) and len(temp_lot) == 10:
            Log.INFO("Performing second lot lookup by replacing 3rd character with 0.")
            chars = list(temp_lot)
            if len(chars) >= 3:
                chars[2] = "0"
            header.LOT = "".join(chars)
            if self._try_populate(header, base_url):
                return True

        temp_lot = orig_lot
        if len(temp_lot) > 8 and not re.match(r"^M0", temp_lot, re.I):
            Log.INFO("Performing second lot lookup using first 8 characters of KG|KH lots.")
            header.LOT = temp_lot[:8]
            if self._try_populate(header, base_url):
                return True
            Log.INFO("Performing third lot lookup by stripping last character if KG|KH lots.")
            header.LOT = orig_lot[:-1]
            if self._try_populate(header, base_url):
                return True

        if re.match(r"^L", orig_lot) and re.search(r"A$", orig_lot) and len(orig_lot) > 5:
            Log.INFO("New Rule: Lot starts with L, ends with A, longer than 5 characters.")
            header.LOT = orig_lot[:-1]
            if self._try_populate(header, base_url):
                return True

        return False

    def _utac_filename_retry(self, header, base_url, infile):
        Log.INFO("Performing second lot lookup using lot in filename.")
        parts = basename(infile).split("_")
        if len(parts) > 1:
            header.LOT = parts[1].strip()
            return self._try_populate(header, base_url)
        return False


def create_from_config(config_data, ws_source="prod"):
    ws_source = (ws_source or "prod").lower()
    ws_cfg = config_data.get("WS_Refdb_Client", {})
    client = RefdbAPIClient(
        retries=ws_cfg.get("retries", 5),
        backoff_factor=ws_cfg.get("backoff_factor", 0.5),
        status_forcelist=tuple(ws_cfg.get("status_forcelist", [500, 502, 504])),
    )
    default_onlot = config_data.get("default_onlot_prod")
    return EagleMetadataPopulator(
        refdb_client=client,
        default_onlot_prod=default_onlot,
        ws_timeout=ws_cfg.get("timeout", 5.0),
    )


def resolve_ert_base_url(facility_ert_url, location, config_data=None):
    """Prefer onLotProd from facility INI; fall back to YAML location section."""
    if facility_ert_url:
        return facility_ert_url
    if not config_data or not location:
        return None
    section = config_data.get(location) or config_data.get(location.upper())
    if isinstance(section, dict):
        return section.get("onLotProd") or section.get("onlotprod")
    return None
