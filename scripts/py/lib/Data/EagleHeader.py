"""
Header fields used by Eagle log translators (Perl HeaderLong equivalent).
"""

from datetime import datetime
from lib.Data.Base import Base
from lib.Log import Log
from lib.Util import Util


class EagleHeader(Base):
    ATTRS = [
        "isFinalLot", "isRelLot", "ertUrl",
        "VERSION", "CREATION_DATE", "PROGRAM_CLASS", "PROGRAM", "RELEASE", "REVISION",
        "FAB", "TECHNOLOGY", "FAMILY", "PROCESS", "PRODUCT", "PACKAGE", "STEP", "STAGE",
        "STEP_GRP1", "STEP_GRP2", "STEP_GRP3", "LOT", "SOURCE_LOT", "LOT_CLASS", "DATE_CODE",
        "TECHNOLOGY", "LOT_TYPE",
        "EQUIP1_ID", "EQUIP2_ID", "EQUIP3_ID", "EQUIP4_ID", "EQUIP5_ID", "EQUIP6_ID",
        "CFG_TESTER_TYPE", "INDEX1", "INDEX2", "OPERATOR", "START_TIME", "END_TIME",
        "DEVICE_COUNT",
    ]

    def __init__(self, args=None):
        args = args or {}
        super().__init__(args)
        for attr in self.ATTRS:
            if not hasattr(self, attr):
                setattr(self, attr, args.get(attr, "NA"))
        self.CREATION_DATE = datetime.now().strftime("%Y/%m/%d %H:%M:%S")

    def array(self):
        return []

    def list(self):
        return [a for a in self.ATTRS if a not in ("isFinalLot", "isRelLot", "ertUrl")]

    def populate_metadata_ert(self, metadata_dict):
        """Apply onLot/onProd fields from ERT Reference Tables WS response."""
        if not self.LOT:
            Log.WARN("LOT is not initialized")
            return False
        if not metadata_dict:
            Log.WARN("ERT metadata response is empty")
            return False

        on_lot = metadata_dict.get("onLot") or {}
        status = str(on_lot.get("status", "")).upper()
        if status in ("NO_DATA", "ERROR", "NO_LOTG", "NOLOTG", "NODATA"):
            Log.INFO(f"metadata not found on ERT (status={status})")
            return False
        if status == "FOUND":
            Log.INFO(f"Good. Meta Found for Lot = {self.LOT} on ERT")
            self._apply_on_lot_prod_response(metadata_dict)
            return self._has_product_metadata()
        Log.WARN(f"Unexpected ERT onLot status={status}")
        return False

    def _apply_on_lot_prod_response(self, decoded_json):
        on_lot = decoded_json.get("onLot") or {}
        on_prod = decoded_json.get("onProd") or {}

        fab = Util.rep_na(on_lot.get("fab"))
        if fab and fab != "NA":
            self.FAB = fab

        self.SOURCE_LOT = Util.formatSourceLot(on_lot.get("sourceLot"), self.LOT)
        self.FAMILY = Util.rep_na(on_prod.get("family") or self.FAMILY)
        self.PROCESS = Util.rep_na(on_prod.get("process") or self.PROCESS)
        self.PACKAGE = Util.rep_na(on_prod.get("package") or self.PACKAGE)
        self.LOT_CLASS = Util.rep_na(on_lot.get("lotClass") or self.LOT_CLASS)
        self.TECHNOLOGY = Util.rep_na(on_prod.get("technology") or getattr(self, "TECHNOLOGY", "NA"))

        product = on_prod.get("product") or on_lot.get("product")
        if product and str(product).strip() not in ("", "NA", "N/A", "None", "null"):
            self.PRODUCT = Util.rep_na(product)
        elif not self.PRODUCT or self.PRODUCT in ("NA", "N/A"):
            self.PRODUCT = Util.rep_na(product) if product else self.PRODUCT

        parent_product = on_lot.get("parentProduct")
        if parent_product and str(parent_product).strip() not in ("", "NA", "N/A"):
            self.STEP = Util.rep_na(getattr(self, "STEP", "NA"))

    def _has_product_metadata(self):
        product = getattr(self, "PRODUCT", None)
        if product and str(product).strip() not in ("", "NA", "N/A", "None"):
            return True
        if getattr(self, "FAB", "") and "CZ4:" in str(self.FAB).upper():
            return True
        Log.WARN("Product not available from ERT metadata..sending to sandbox.")
        return False
