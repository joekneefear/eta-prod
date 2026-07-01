"""
Site-specific Eagle log post-processing (port of fcs_eagle_log_IFF.pl given/when blocks).
"""

import os
import re
from os.path import basename
from lib.Log import Log
from lib.Util import Util
from lib.Data.Rel import Rel
from lib.Utility.EagleTestFlow import add_test_flow_to_tp, TF_SITES


VALID_SITES = {
    "cpft", "szrel", "szft", "pmft", "merel", "meft", "aic_my_ft", "atec_ph_ft",
    "etrend_tw_ft", "hana_th_ft", "gtk_tw_ft", "utac_th_ft", "mtsort", "pmsort",
    "casort", "cpsort", "szsort", "slsort", "mesort", "bksort", "amkor_tw_csp",
    "isti_tw_csp", "isti_tw_sort_mosaic_bk", "its_tw_ft", "gtk_tw_sort",
    "vgrd_tw_sort", "cprel", "aseft",
}

TF_PROGRAM_SITES = {
    "gtk_tw_ft", "hana_th_ft", "atec_ph_ft", "isti_tw_csp", "its_tw_ft",
    "amkor_tw_csp", "etrend_tw_ft", "utac_th_ft", "aic_my_ft", "gtk_tw_sort",
    "vgrd_tw_sort",
}


class EagleSiteProcessor:
    def __init__(self, model, writer, parser, site, infile, options=None):
        self.model = model
        self.writer = writer
        self.parser = parser
        self.site = site
        self.infile = infile
        self.options = options or {}
        self.header = model.header
        self.misc = model.misc or {}
        self.test_mode = ""
        self.reglim_flg = "Y"

    @staticmethod
    def _trim(v):
        return str(v).strip() if v is not None else ""

    def _sandbox(self):
        self.writer.forced_sandbox = True
        self.reglim_flg = "N"

    def _misc(self, key):
        return self.misc.get(key) or []

    def _wafer(self):
        return self.model.wafers[0] if self.model.wafers else None

    def _in_range(self, value, low, high):
        try:
            num = float(value)
            return low <= num <= high
        except (TypeError, ValueError):
            return False

    def _process_rel_filename(self):
        base_fn = basename(self.infile)
        base_fn = re.sub(r"\.LOG.*", "", base_fn, flags=re.I)
        parts = base_fn.split("_")
        if len(parts) < 5:
            return
        strname, strdur, temp, dtype = parts[1], parts[2], parts[3], parts[4]
        if re.search(r"[0-9]", dtype or ""):
            dtype = ""
        qpnum = devchar = lotchar = ""
        if re.match(r"^20", parts[0]):
            qpnum = parts[0][:8]
            devchar = parts[0][8:9] if len(parts[0]) > 8 else ""
            lotchar = parts[0][9:10] if len(parts[0]) > 9 else ""
            self.header.LOT = qpnum + devchar + lotchar
        elif re.match(r"^[UW]", parts[0], re.I):
            qpnum = parts[0][:6]
            lotchar = parts[0][-1:]
            self.header.LOT = qpnum + lotchar
        if not self._in_range(strdur, 0, 1000000) or re.search(r"\D", strdur or ""):
            Log.WARN(f"Stress Duration not in range = {strdur}")
            if re.search(r"[a-z]", strdur or "", re.I):
                strdur = ""
            self._sandbox()
        if not self._in_range(temp, -1000000, 1000000) or re.search(r"\D", temp or ""):
            Log.WARN(f"ATETemp not in range = {temp}")
            if re.search(r"[a-z]", temp or "", re.I):
                temp = ""
            self._sandbox()
        self.header.INDEX1 = f"{strname}_{strdur}_{temp}_{dtype}"
        rel = Rel({
            "qpnumber": qpnum, "devchar": devchar, "lotchar": lotchar,
            "strname": strname, "strduration": strdur, "atetemp": temp, "datalogtype": dtype,
        })
        self.model.add("rels", rel)

    def apply_site_rules(self):
        site = self.site
        h = self.header
        w = self._wafer()

        if site == "pmsort":
            item = self._misc("125_W")
            pkg = self._misc("125")
            if len(item) > 5:
                boards = item[5].split(";")
                if len(boards) >= 2:
                    h.EQUIP3_ID = self._trim(boards[1])
                    h.EQUIP4_ID = self._trim(boards[0])
                h.EQUIP5_ID = self._trim(item[4])
            if len(pkg) > 1 and self._trim(pkg[1]) == "P":
                Log.WARN(f"Wrong package type:{pkg[1]}. Sending to sandbox.")
                self._sandbox()
            item120 = self._misc("120")
            if w and len(item120) > 6:
                w.number = self._trim(item120[6])
            h.LOT = re.sub(r"[._]", "", h.LOT or "")
            h.PROGRAM_CLASS = 1

        elif site == "mtsort":
            item = self._misc("125_W")
            if len(item) > 6:
                h.EQUIP2_ID = h.EQUIP3_ID = self._trim(item[4])
                h.EQUIP4_ID = self._trim(item[5])
                h.EQUIP5_ID = self._trim(item[4])
            item120 = self._misc("120")
            if w and len(item120) > 6:
                w.number = self._trim(item120[6])
            h.PROGRAM = "EL" + (h.PROGRAM or "")
            h.PROGRAM_CLASS = 1

        elif site == "isti_tw_csp":
            item = self._misc("120")
            if len(item) > 6:
                lot_part, _ = (item[5] + "-").split("-", 1)
                wafer_part = item[6].split("-")[-1] if "-" in item[6] else item[6]
                wafer_num = re.split(r"[A-Za-z]", wafer_part)[0]
                self.test_mode = self._trim(item[5].strip('"')).split("-")[-1] if "-" in item[5] else ""
                h.LOT = self._trim(lot_part)
                if w:
                    w.number = self._trim(wafer_num)
            h.PROGRAM_CLASS = 1

        elif site == "isti_tw_sort_mosaic_bk":
            item_a, item_b = self._misc("120"), self._misc("125")
            if len(item_b) > 1 and self._trim(item_b[1]) == "P":
                self._sandbox()
            elif len(item_b) > 6 and self._trim(item_b[1]) == "W":
                h.EQUIP3_ID = self._trim(item_b[6])
                h.EQUIP4_ID = self._trim(item_b[5])
                h.EQUIP5_ID = re.sub(r"[^0-9a-z]", "", self._trim(item_b[4]), flags=re.I)
            if w and len(item_a) > 6:
                w.number = self._trim(item_a[6])
            h.PROGRAM_CLASS = 1

        elif site == "its_tw_ft":
            item = self._misc("120")
            if len(item) > 5:
                h.LOT = self._trim(item[5].strip('"').split("-")[0])
            h.PROGRAM_CLASS = 2

        elif site == "amkor_tw_csp":
            item_a, item_b = self._misc("120"), self._misc("125_W")
            if len(item_a) > 5:
                h.LOT = self._trim(item_a[5].split("-")[0])
            new_lot = (h.LOT or "").replace(".", "")
            new_lot = re.sub(r"\-.*", "", new_lot)
            h.LOT = new_lot
            if len(item_b) > 5:
                h.EQUIP4_ID = self._trim(item_b[5])
            if w and len(item_a) > 6:
                w.number = self._trim(item_a[6])
            h.PROGRAM_CLASS = 1

        elif site == "pmft":
            base_fn = basename(self.infile)
            item_a = self._misc("125")
            item_b = self._misc("ghr_info")
            h.LOT = re.sub(r"[._]", "", h.LOT or "")
            h.PROGRAM = (h.PROGRAM or "") + ("_QA" if "QA_ETS" in base_fn else "_FT")
            h.PROGRAM_CLASS = 2
            if len(item_a) > 5 and self._trim(item_a[5]):
                boards = item_a[5].strip('"').split(";")
                if len(boards) >= 2:
                    h.EQUIP3_ID, h.EQUIP4_ID = self._trim(boards[1]), self._trim(boards[0])
            else:
                for addr in item_b:
                    if re.search(r"Loadboard", addr, re.I):
                        h.EQUIP4_ID = self._trim(addr.split(":", 1)[-1])
                    if re.search(r"Probecard", addr, re.I):
                        h.EQUIP3_ID = self._trim(addr.split(":", 1)[-1])

        elif site == "szft":
            lot = h.LOT or ""
            item120 = self._misc("120")
            raw_lot = item120[5] if len(item120) > 5 else lot
            lot = lot.replace("AO", "A0")
            if re.search(r"REJ|RETEST", lot, re.I):
                h.INDEX2 = "O"
                self.reglim_flg = "N"
                lot = re.sub(r"(REJ|RETEST).*$", "", lot, flags=re.I)
            raw_base = re.sub(r"(REJ|RETEST).*$", "", raw_lot, flags=re.I)
            if raw_base.endswith("r"):
                lot = re.sub(r"R$", "", lot, flags=re.I)
            elif lot.endswith("R"):
                lot = lot[:-1]
            if len(lot) > 10:
                lot = lot[:10]
            m = re.match(r"^([[:ascii:]]{10})\.(\d+)$", lot)
            if m:
                lot = m.group(1)
            h.LOT = self._trim(lot)
            h.PROGRAM = "EGL_" + (h.PROGRAM or "")
            h.PROGRAM_CLASS = 2
            for addr in self._misc("ghr_info"):
                if "FT Station" in addr:
                    h.PROGRAM += "_FT"
                if "QA Station" in addr:
                    h.PROGRAM += "_QA"
                if "|" in addr:
                    lb, dut = re.split(r"\s?\|\s?", addr, 1)
                    h.EQUIP4_ID = self._trim(lb)
                    h.INDEX1 = self._trim(dut)
            item120 = self._misc("120")
            if len(item120) > 8:
                station = self._trim(item120[8])
                if re.search(r".+AC|.+DC", station, re.I):
                    h.PROGRAM += "::" + station
            rev = getattr(h, "REVISION", "")
            if rev:
                h.PROGRAM += "::" + str(rev)

        elif site in ("szrel", "merel"):
            h.PROGRAM_CLASS = 2
            base_fn = re.sub(r"\.LOG.*", "", basename(self.infile), flags=re.I)
            parts = base_fn.split("_")
            if site == "szrel" and parts:
                h.PROGRAM = parts[0]
            self._process_rel_filename()

        elif site == "cpft":
            base_fn = basename(self.infile)
            for brd in re.split(r"[_\.]", base_fn):
                if brd.startswith("FTFAM"):
                    h.EQUIP4_ID = self._trim(brd)
            h.PROGRAM = "EGL_" + (h.PROGRAM or "")
            for addr in self._misc("ghr_info"):
                if "FT Station" in addr:
                    h.PROGRAM += "_FT"
                if "QA Station" in addr:
                    h.PROGRAM += "_QA"
            h.PROGRAM_CLASS = 2
            lot = h.LOT or ""
            if re.match(r"^[[:alnum:]]+_[[:alnum:]]+-[[:digit:]]+_[[:alnum:]]+-[[:digit:]]+$", lot):
                h.LOT = lot.split("_")[0]
            if re.search(r"_FT$", lot, re.I):
                h.LOT = re.sub(r"_FT", "", lot, flags=re.I)

        elif site == "meft":
            h.PROGRAM_CLASS = 2
            base_fn = re.sub(r"\.LOG.*", "", basename(self.infile), flags=re.I)
            parts = base_fn.split("_")
            if parts:
                h.LOT = parts[0]

        elif site == "cprel":
            h.PROGRAM_CLASS = 2
            base_fn = re.sub(r"\.LOG.*", "", basename(self.infile), flags=re.I)
            parts = base_fn.split("_")
            if len(parts) >= 5:
                strname, strdur, temp, dtype = parts[1], parts[2], parts[3], parts[4]
                if re.search(r"[0-9]", dtype):
                    dtype = ""
                qpnum = devchar = lotchar = ""
                if re.match(r"^20", parts[0]):
                    qpnum, devchar, lotchar = parts[0][:8], parts[0][-2:-1], parts[0][-1:]
                    h.LOT = qpnum + devchar + lotchar
                elif parts[0].upper().startswith("F"):
                    qpnum, lotchar = parts[0][:6], parts[0][-1:]
                    h.LOT = qpnum + lotchar
                if not self._in_range(strdur, 0, 1000000) or re.search(r"\D", strdur or ""):
                    Log.WARN(f"Stress Duration not in range = {strdur}")
                    if re.search(r"[a-z]", strdur or "", re.I):
                        strdur = ""
                    self._sandbox()
                if not self._in_range(temp, -1000000, 1000000) or re.search(r"\D", temp or ""):
                    Log.WARN(f"ATETemp not in range = {temp}")
                    if re.search(r"[a-z]", temp or "", re.I):
                        temp = ""
                    self._sandbox()
                h.INDEX1 = f"{strname}_{strdur}_{temp}_{dtype}"
                self.model.add("rels", Rel({
                    "qpnumber": qpnum, "devchar": devchar, "lotchar": lotchar,
                    "strname": strname, "strduration": strdur, "atetemp": temp, "datalogtype": dtype,
                }))

        elif site == "aic_my_ft":
            h.PROGRAM_CLASS = 2

        elif site == "atec_ph_ft":
            lot_parts = (h.LOT or "").split("_")
            h.LOT = self._trim(lot_parts[0])
            self.test_mode = self._trim(lot_parts[2]) if len(lot_parts) > 2 else ""
            item_a = self._misc("125")
            if len(item_a) > 6:
                h.EQUIP4_ID = self._trim(item_a[6])
            h.PROGRAM_CLASS = 2

        elif site == "etrend_tw_ft":
            lot = re.sub(r"\.LOG", "", h.LOT or "", flags=re.I)
            parts = lot.split("_")
            chosen = parts[0] if parts and len(parts[0]) >= 5 else ""
            if not chosen:
                for p in parts[1:]:
                    if len(p) >= 5:
                        chosen = p
                        break
            h.LOT = chosen
            h.PROGRAM_CLASS = 2

        elif site == "hana_th_ft":
            parts = (h.LOT or "").split("_")
            h.LOT = self._trim(parts[0])
            self.test_mode = self._trim(parts[1]) if len(parts) > 1 else ""
            h.PROGRAM_CLASS = 2

        elif site == "gtk_tw_ft":
            base_fn = basename(self.infile)
            arr = base_fn.split("_")
            seen = {x for x in arr if arr.count(x) > 1}
            dup = bool(seen)
            if dup and len(arr) >= 5:
                h.LOT = arr[0]
            elif len(arr) >= 1:
                h.LOT = arr[0]
            h.PROGRAM_CLASS = 2

        elif site == "utac_th_ft":
            lot_parts = (h.LOT or "").split("_", 1)
            self.test_mode = lot_parts[1] if len(lot_parts) > 1 else ""
            if self.parser.sublot and not re.match(r"^<not specified>$", str(self.parser.sublot), re.I):
                h.LOT = self._trim(self.parser.sublot)
            for addr in self._misc("ghr_info"):
                if "CUST-ASSY-LOT" in addr:
                    h.LOT = self._trim(addr.split(":", 1)[-1])
                elif re.search(r"HANDLER\sID\sFOR\sSITE1", addr):
                    h.EQUIP5_ID = self._trim(addr.split(":", 1)[-1])
            h.LOT = self._trim((h.LOT or "").split("_")[0])
            h.PROGRAM_CLASS = 2

        elif site == "gtk_tw_sort":
            item = self._misc("120")
            if len(item) > 6 and w:
                w.number = self._trim(item[6].split("-")[-1])
            h.LOT = (h.LOT or "").split("-")[0]
            h.PROGRAM_CLASS = 1

        elif site == "cpsort":
            pkg, item = self._misc("125"), self._misc("120")
            base_fn = basename(self.infile)
            if h.LOT and h.LOT.lower() not in base_fn.lower():
                Util.dp_exit(1, f"Lotid: {h.LOT} is not found in the filename")
            if len(pkg) > 1 and self._trim(pkg[1]) == "P":
                self._sandbox()
            if len(pkg) > 5:
                brd = re.split(r"\D+", pkg[5])
                if len(brd) > 4:
                    h.EQUIP3_ID = brd[4]
                if len(brd) > 1:
                    h.EQUIP4_ID = brd[1]
            if w and len(item) > 6:
                w.number = self._trim(item[6])
            h.PROGRAM_CLASS = 1

        elif site in ("szsort", "casort"):
            pkg, item = self._misc("125"), self._misc("120")
            if len(pkg) > 1 and self._trim(pkg[1]) == "P":
                self._sandbox()
            if w and len(item) > 6:
                w.number = self._trim(item[6])
            h.PROGRAM_CLASS = 1

        elif site == "mesort":
            item_a, item_b = self._misc("120"), self._misc("125")
            if len(item_b) > 1 and self._trim(item_b[1]) == "P":
                self._sandbox()
            if len(item_b) > 5:
                boards = item_b[5].split(";")
                if len(boards) >= 2:
                    h.EQUIP3_ID, h.EQUIP4_ID = self._trim(boards[1]), self._trim(boards[0])
                h.EQUIP5_ID = self._trim(item_b[4])
            if w and len(item_a) > 6:
                w.number = self._trim(item_a[6])
            h.PROGRAM_CLASS = 1

        elif site == "bksort":
            item_a, item_b = self._misc("120"), self._misc("125")
            if len(item_b) > 1 and self._trim(item_b[1]) == "P":
                self._sandbox()
            elif len(item_b) > 6 and self._trim(item_b[1]) == "W":
                h.EQUIP3_ID = self._trim(item_b[6])
                h.EQUIP4_ID = self._trim(item_b[5])
                h.EQUIP5_ID = re.sub(r"[^0-9a-z]", "", self._trim(item_b[4]), flags=re.I)
            if w and len(item_a) > 6:
                w.number = self._trim(item_a[6])
            h.PROGRAM_CLASS = 1

        elif site == "slsort":
            item_a = self._misc("120")
            for addr in self._misc("ghr_info"):
                if addr.startswith("PCARD"):
                    h.EQUIP3_ID = addr.replace("PCARD_", "")
            if w and len(item_a) > 6:
                w.number = self._trim(item_a[6])
            h.PROGRAM_CLASS = 1

        elif site == "vgrd_tw_sort":
            item = self._misc("120")
            if w and len(item) > 6:
                w.number = self._trim(item[6])
            h.PROGRAM_CLASS = 1

        elif site == "aseft":
            h.PROGRAM_CLASS = 2
            arr = basename(self.infile).split("_")
            if len(arr) > 1:
                h.LOT = self._trim(arr[1])

    def apply_program_rules(self, cfg_tester_type, script_dir):
        h = self.header
        h.CFG_TESTER_TYPE = cfg_tester_type or ""
        ref_file = os.path.join(script_dir, "testFlow.ref")
        tf_code = add_test_flow_to_tp(self.model, self.test_mode, self.site, ref_file)
        program = h.PROGRAM or ""
        suffix = f"_{tf_code}" if tf_code else ""
        if self.site in TF_PROGRAM_SITES:
            if len(program) + len(suffix) > 235:
                Log.WARN("PROGRAM NAME will be truncated to 235 characters. Sending to sandbox.")
                self._sandbox()
                program = program[: max(0, 234 - len(suffix))]
            program = program + suffix
        elif len(program) > 235:
            Log.WARN("PROGRAM NAME will be truncated to 235 characters. Sending to sandbox.")
            self._sandbox()
            program = program[:234]
        program = re.sub(r"_$", "", program)
        h.PROGRAM = program
        if getattr(self.model, "forSBflag", None) == 1:
            self._sandbox()

    def validate_results(self, is_rellot=False):
        w = self._wafer()
        if not w:
            Util.dp_exit(1, "No wafer data in model")
        stats = w.stats()
        if stats.get("deviceCount", 0) == 0:
            Util.dp_exit(1, f"Zero devices to create SXML ({stats.get('deviceCount', 0)})")
        if stats.get("deviceCount", 0) <= 1 and not is_rellot:
            Log.WARN(f"Too few devices.Sending to sandbox... ({stats.get('deviceCount', 0)})")
            self._sandbox()
            self.reglim_flg = "N"
        passcount = self.misc.get("passcount", 0)
        if not passcount:
            Log.WARN("All parts tested FAILED!")
        else:
            Log.INFO(f"{passcount} parts PASSED!")
        return stats
