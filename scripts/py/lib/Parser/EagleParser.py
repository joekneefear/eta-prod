"""
Eagle log file parser (Python port of PDF::Parser::Eagle).
"""

import re
from time import mktime
from lib.Data.Base import Base
from lib.Data.Model import Model
from lib.Data.EagleHeader import EagleHeader
from lib.Data.Wafer import Wafer
from lib.Data.Test import Test
from lib.Data.Die import Die
from lib.Data.Bin import Bin
from lib.Data.Wmap import Wmap
from lib.Log import Log
from lib.Util import Util


class EagleParser(Base):
    """Parse Eagle comma-separated log records into a data Model."""

    def __init__(self, args=None):
        super().__init__(args or {})
        self.sublot = None

    @staticmethod
    def _trim(value):
        return str(value).strip() if value is not None else ""

    @staticmethod
    def _rep_na(value):
        text = EagleParser._trim(value)
        return "NA" if text == "" else text

    @staticmethod
    def _convert_datetime_to_seconds(dt):
        parts = re.split(r"[/\s:]+", str(dt).strip())
        if len(parts) < 6:
            return 0
        mm, dd, yy = int(parts[0]), int(parts[1]), int(parts[2])
        hr, minute, sec = int(parts[4]), int(parts[5]), int(parts[6]) if len(parts) > 6 else 0
        return int(mktime((yy, mm, dd, hr, minute, sec, 0, 0, 0)))

    def read_file(self, infile, site):
        header = EagleHeader()
        wmap = Wmap()
        model = Model(
            {
                "header": header,
                "wmap": wmap,
                "misc": {},
                "dataSource": "EAGLE",
            }
        )
        wafer = Wafer()
        model.add("wafers", wafer)

        data = {}
        data2 = {}
        ghr = []
        die_cnt = 0
        record5_cnt = 0
        record5_key = None
        prev_part_test_time_sec = ""
        prev_part_test_time = 0
        first_part_test_time_sec = None
        touchdown_num = 0
        td = {}
        sb_cnt = {}
        hb_cnt = {}
        sbr = {}
        hbr = {}
        rec50_flg = "N"
        rec60_flg = "N"
        sbox_flg = 0
        pkg_type = None
        auto_partid = 100000
        ft_part_id = 0
        p_cnt = 0
        site_l = (site or "").lower()

        with open(infile, "r", encoding="utf-8", errors="replace") as infile_handle:
            for raw_line in infile_handle:
                item = raw_line.strip().split(",")
                if not item:
                    continue
                rec = item[0]

                if rec == "10":
                    for num, name, units in (("0.1", "test_time", "sec"), ("0.2", "elapsed_time", "sec")):
                        if wafer.find("tests", {"number": num}) is None:
                            t = Test({"number": num, "name": name, "units": units})
                            wafer.add("tests", t)
                    test = Test(
                        {
                            "number": item[1],
                            "name": self._rep_na(item[6] if len(item) > 6 else ""),
                            "units": self._rep_na(item[5] if len(item) > 5 else ""),
                            "group": self._rep_na(item[2] if len(item) > 2 else ""),
                            "LSL": self._rep_na(item[4] if len(item) > 4 else ""),
                            "HSL": self._rep_na(item[3] if len(item) > 3 else ""),
                        }
                    )
                    wafer.add("tests", test)
                    if len(item) > 6 and (item[6] == "" or item[6] == "N/A"):
                        model.misc["err_msg"] = "Test name should not be blank."

                elif rec == "11" and site_l == "szft" and record5_key is None and len(item) > 1:
                    record5_key = item[1]

                elif rec == "5" and site_l == "szft" and record5_key is not None and len(item) > 2:
                    if item[1] == record5_key:
                        record5_cnt += 1
                        data2[record5_cnt] = item[2]

                elif rec == "100" and len(item) > 4:
                    data[item[1]] = item[4]

                elif rec == "130" and len(item) > 8:
                    die_cnt += 1
                    item[2] = item[2].replace('"', "")
                    current_sec = self._convert_datetime_to_seconds(item[2])
                    if prev_part_test_time_sec == "":
                        prev_part_test_time_sec = current_sec
                    if die_cnt == 1:
                        touchdown_num = 1
                        first_part_test_time_sec = current_sec
                        test_time = current_sec - prev_part_test_time_sec
                        prev_part_test_time = test_time
                    elif current_sec == prev_part_test_time_sec:
                        test_time = prev_part_test_time
                    else:
                        test_time = current_sec - prev_part_test_time_sec
                        prev_part_test_time = test_time
                        touchdown_num += 1
                    elapsed = current_sec - (first_part_test_time_sec or current_sec)
                    data["0.1"] = test_time
                    data["0.2"] = elapsed
                    prev_part_test_time_sec = current_sec

                    if site_l and not site_l.endswith("ft") and "sort" in site_l:
                        if not re.search(r"[0-9]", item[3]):
                            if not sbox_flg:
                                sbox_flg = 1
                                Log.WARN("PartNo Not Specified..sending file to sandbox")
                        if not re.search(r"[0-9]", item[3]):
                            item[3] = str(auto_partid)
                            auto_partid += 1
                    else:
                        ft_part_id += 1

                    ecid = data2.get(die_cnt)
                    if pkg_type == "P":
                        if "sort" in site_l or "_csp" in site_l:
                            if (not item[5]) or (not item[6]):
                                model.misc["err_msg"] = "No X/Y coordinates found."
                        td[ft_part_id] = {
                            "x": item[5], "y": item[6], "site": item[1], "ecid": ecid,
                            "pf": item[4], "sbin": item[7], "hbin": item[8], "result": dict(data),
                        }
                        die = Die({
                            "x": item[5], "y": item[6], "site": item[1], "partid": ft_part_id,
                            "touchdown_num": touchdown_num, "ecid": ecid,
                            "soft_bin": item[7], "hard_bin": item[8],
                        })
                        for t in wafer.tests:
                            die.add("result", self._rep_na(data.get(t.number)))
                        wafer.add("dies", die)
                    elif pkg_type == "W":
                        if (not item[5]) or (not item[6]):
                            model.misc["err_msg"] = "No X/Y coordinates found."
                        xy = f"x{item[5]}y{item[6]}"
                        td[xy] = {
                            "x": item[5], "y": item[6], "partid": item[3], "site": item[1],
                            "pf": item[4], "sbin": item[7], "hbin": item[8], "result": dict(data),
                        }
                        die = Die({
                            "x": item[5], "y": item[6], "site": item[1], "partid": item[3],
                            "touchdown_num": touchdown_num,
                            "soft_bin": item[7], "hard_bin": item[8],
                        })
                        for t in wafer.tests:
                            die.add("result", self._rep_na(data.get(t.number)))
                        wafer.add("dies", die)

                    data = {}
                    data2 = {}
                    if not wafer.START_TIME:
                        wafer.START_TIME = item[2]
                    wafer.END_TIME = item[2]

                elif rec == "50" and len(item) > 4:
                    rec50_flg = "Y"
                    sbr[item[1]] = {"name": self._trim(item[4])}

                elif rec == "60" and len(item) > 4:
                    rec60_flg = "Y"
                    hbr[item[1]] = {"name": self._trim(item[4])}

                elif rec == "120" and len(item) > 8:
                    model.misc["120"] = item
                    lot = re.sub(r"[\n\$\%\^\&\*\{\}\[\]\|\!\~\/\`\<\>\:\;\"\,\'\\]", "", item[5])
                    header.LOT = self._trim(lot.upper())
                    self.sublot = item[6]
                    header.OPERATOR = self._trim(item[7])
                    header.EQUIP1_ID = self._trim(
                        f"{self._trim(item[2])} {self._trim(item[8])} {self._trim(item[1])}"
                    )

                elif rec == "140" and len(item) > 4 and item[1] == "2":
                    model.misc["140_2"] = item
                    program = self._trim(item[2]).replace("\\", "/")
                    header.PROGRAM = program.split("/")[-1].split(".")[0]
                    header.REVISION = self._trim(item[4])
                    header.PRODUCT = self._trim(item[3].upper())

                elif rec == "125" and len(item) > 1:
                    item[1] = item[1].replace('"', "")
                    model.misc["125"] = item
                    if item[1] == "W":
                        model.misc["125_W"] = item
                        pkg_type = "W"
                    elif item[1] == "P":
                        model.misc["125_P"] = item
                        pkg_type = "P"

                elif rec == "145" and len(item) > 2:
                    ghr.extend([self._trim(item[1]), self._trim(item[2])])
                    model.misc["ghr_info"] = ghr

        if rec50_flg == "N" or rec60_flg == "N":
            sbox_flg = 1
            Log.WARN("No record 50 or 60 found..sending file to sandbox")

        for key in sorted(td.keys(), key=lambda k: int(k) if str(k).isdigit() else str(k)):
            entry = td.get(key)
            if not entry:
                continue
            sb_cnt[entry["sbin"]] = sb_cnt.get(entry["sbin"], 0) + 1
            hb_cnt[entry["hbin"]] = hb_cnt.get(entry["hbin"], 0) + 1
            sbin = wafer.find("bins", {"number": entry["sbin"]})
            if sbin is None:
                sbin = Bin()
                wafer.add("bins", sbin)
            sbin.number = entry["sbin"]
            sbin.name = (
                sbr.get(entry["sbin"], {}).get("name")
                if rec50_flg == "Y"
                else f"SBIN{entry['sbin']}"
            )
            sbin.PF = entry["pf"]
            sbin.count = sb_cnt[entry["sbin"]]
            hbin = wafer.find("hbins", {"number": entry["hbin"]})
            if hbin is None:
                hbin = Bin()
                wafer.add("hbins", hbin)
            hbin.number = entry["hbin"]
            hbin.name = (
                hbr.get(entry["hbin"], {}).get("name")
                if rec60_flg == "Y"
                else f"HBIN{entry['hbin']}"
            )
            hbin.PF = entry["pf"]
            hbin.count = hb_cnt[entry["hbin"]]
            if re.search(r"P", str(entry["pf"]), re.I):
                p_cnt += 1
        model.misc["passcount"] = p_cnt
        return model, sbox_flg
