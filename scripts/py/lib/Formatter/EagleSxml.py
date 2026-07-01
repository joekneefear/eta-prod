"""
Build Eagle log output in STDML / SXML format (not IFF).

Canonical structure (SXML_Format_File_Mapping.xlsx / production samples):
  Xml > File > [Metadata] > Lot > Wmc, Sites, Parameters,
  SummaryData (PartInfo, BinInfo, TestInfo), ParametricData (Unit/Meas)
"""

import html
from lib.Util import Util


class EagleSxml:
    """Emit production-style SXML from an Eagle data model."""

    SUMMARY_SITE = "255"
    SUMMARY_HEAD = "255"

    def __init__(self, model=None, input_filename=None):
        self.model = model
        self.input_filename = input_filename or "NA"

    @staticmethod
    def _esc(value):
        if value is None:
            return ""
        text = str(value).strip()
        if text in ("", "NA", "N/A", "None", "null"):
            return ""
        return html.escape(text, quote=True)

    @staticmethod
    def _attr(name, value):
        esc = EagleSxml._esc(value)
        return f'{name}="{esc}"' if esc else ""

    def _attrs(self, pairs):
        return " ".join(p for p in (self._attr(k, v) for k, v in pairs if v is not None) if p)

    @staticmethod
    def _pf_code(pf):
        if pf is None:
            return "0"
        return "0" if str(pf).upper().startswith("P") else "1"

    def _meas_pf(self, raw, test):
        val = self._to_float(raw)
        lsl = self._to_float(getattr(test, "LSL", ""))
        hsl = self._to_float(getattr(test, "HSL", ""))
        if val is not None and (lsl is not None or hsl is not None):
            if lsl is not None and val < lsl:
                return "1"
            if hsl is not None and val > hsl:
                return "1"
            return "0"
        if val is not None:
            return "0"
        return "1"

    @staticmethod
    def _to_float(value):
        try:
            return float(str(value).strip())
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _bin_display_name(bin_type, number, name):
        if name and str(name).strip() not in ("", "NA"):
            return str(name).strip()
        num = str(number).strip()
        prefix = "HWBin" if bin_type == "Hardware" else "SWBin"
        return f"{prefix}_{num.zfill(3)}"

    def _metadata_lines(self):
        header = self.model.header
        attrs = [
            ("LotId", getattr(header, "LOT", ""), "EAGLE"),
            ("Product", getattr(header, "PRODUCT", ""), "ERT"),
            ("SourceLot", getattr(header, "SOURCE_LOT", ""), "ERT"),
            ("Family", getattr(header, "FAMILY", ""), "ERT"),
            ("Process", getattr(header, "PROCESS", ""), "ERT"),
            ("Technology", getattr(header, "TECHNOLOGY", ""), "ERT"),
            ("Fab", getattr(header, "FAB", ""), "ERT"),
            ("Facility", getattr(header, "EQUIP6_ID", ""), "EAGLE"),
            ("ProbeProgramName", getattr(header, "PROGRAM", ""), "EAGLE"),
            ("ProgramRevision", getattr(header, "REVISION", ""), "EAGLE"),
            ("Operator", getattr(header, "OPERATOR", ""), "EAGLE"),
            ("LoadBoard", getattr(header, "EQUIP4_ID", ""), "EAGLE"),
            ("ProbeCard", getattr(header, "EQUIP3_ID", ""), "EAGLE"),
            ("Handler", getattr(header, "EQUIP5_ID", ""), "EAGLE"),
            ("Tester", getattr(header, "EQUIP1_ID", ""), "EAGLE"),
        ]
        lines = ["<Metadata>"]
        for name, value, source in attrs:
            if self._esc(value):
                lines.append(
                    f'<Attribute Name="{self._esc(name)}" Value="{self._esc(value)}" '
                    f'Source="{self._esc(source)}"></Attribute>'
                )
        lines.append("</Metadata>")
        return lines

    def _wmc_lines(self):
        wmap = self.model.wmap
        if not wmap or not hasattr(wmap, "isEmpty") or wmap.isEmpty():
            return []
        attrs = self._attrs([
            ("WaferDiameter", getattr(wmap, "wf_size", "")),
            ("DieHeight", getattr(wmap, "die_ht", "")),
            ("DieWidth", getattr(wmap, "die_wid", "")),
            ("WaferDieUnits", getattr(wmap, "wf_units", "")),
            ("FlatOrientation", getattr(wmap, "flat", "")),
            ("CenterDieX", getattr(wmap, "center_x", "")),
            ("CenterDieY", getattr(wmap, "center_y", "")),
            ("PositiveDirectionX", getattr(wmap, "positive_x", "")),
            ("PositiveDirectionY", getattr(wmap, "positive_y", "")),
        ])
        return [f"<Wmc {attrs}></Wmc>"] if attrs else []

    def _sites_lines(self, wafer):
        sites = set()
        for die in wafer.dies:
            if getattr(die, "inked", None) or getattr(die, "notest", None):
                continue
            site = getattr(die, "site", None)
            if site not in (None, "", "NA"):
                sites.add(str(site))
        if not sites:
            sites.add("0")
        lines = ["<Sites>"]
        for site in sorted(sites, key=lambda s: (len(s), s)):
            attrs = self._attrs([
                ("Site", site),
                ("Head", "1"),
                ("SiteCount", str(len(sites))),
                ("SiteGroup", "0"),
            ])
            lines.append(f"<Site {attrs}></Site>")
        lines.append("</Sites>")
        return lines

    def _parameters_lines(self, tests):
        lines = ["<Parameters>"]
        for idx, test in enumerate(tests, start=1):
            test_num = getattr(test, "number", idx)
            test_name = getattr(test, "name", "") or f"TEST_{test_num}"
            units = getattr(test, "units", "") or ""
            lsl = getattr(test, "LSL", "")
            hsl = getattr(test, "HSL", "")
            test_type = "F" if str(test_num) in ("0.1", "0.2") else "M"
            attrs = self._attrs([
                ("Id", str(idx)),
                ("TestNumber", str(test_num)),
                ("TestName", test_name),
                ("TestDescription", test_name),
                ("Units", units),
                ("LowLimit", lsl),
                ("HighLimit", hsl),
                ("LowLimitScale", "0"),
                ("HighLimitScale", "0"),
                ("ResultScale", "0"),
                ("TestType", test_type),
            ])
            lines.append(f"<Param {attrs}></Param>")
        lines.append("</Parameters>")
        return lines

    def _compute_test_stats(self, tests, wafer):
        stats = {}
        for idx, test in enumerate(tests, start=1):
            stats[idx] = {
                "values": [], "fail_count": 0, "pm_id": idx,
                "head": self.SUMMARY_HEAD, "site": self.SUMMARY_SITE,
            }
        for die in wafer.dies:
            if getattr(die, "inked", None) or getattr(die, "notest", None):
                continue
            for i, test in enumerate(tests):
                pm_id = i + 1
                raw = die.result[i] if i < len(die.result) else "NA"
                val = self._to_float(raw)
                if val is not None:
                    stats[pm_id]["values"].append(val)
                if self._meas_pf(raw, test) != "0":
                    stats[pm_id]["fail_count"] += 1
        return stats

    def _summary_lines(self, wafer, tests):
        lines = ["<SummaryData>"]
        stats = wafer.stats() if wafer else {}
        device_count = stats.get("deviceCount", 0)
        good_count = self.model.misc.get("passcount", 0) if self.model.misc else 0

        lines.append("<PartInfo>")
        for head in ("1", self.SUMMARY_HEAD):
            site = "0"
            part_attrs = self._attrs([
                ("Site", site),
                ("Head", head),
                ("PartCount", str(device_count)),
                ("GoodCount", str(good_count or 0)),
                ("RetestCount", "0"),
                ("AbortCount", "0"),
                ("FunctionalCount", "0"),
            ])
            lines.append(f"<Part {part_attrs}></Part>")
        lines.append("</PartInfo>")

        lines.append("<BinInfo>")
        if wafer:
            for bintype, bins in (("Hardware", wafer.hbins), ("Software", wafer.bins)):
                for b in bins:
                    num = getattr(b, "number", "")
                    bin_attrs = self._attrs([
                        ("Site", "0"),
                        ("Head", self.SUMMARY_HEAD),
                        ("Type", bintype),
                        ("Number", str(num)),
                        ("Count", str(getattr(b, "count", ""))),
                        ("Name", self._bin_display_name(bintype, num, getattr(b, "name", ""))),
                    ])
                    lines.append(f"<Bin {bin_attrs}></Bin>")
        lines.append("</BinInfo>")

        test_stats = self._compute_test_stats(tests, wafer)
        lines.append("<TestInfo>")
        for pm_id in sorted(test_stats.keys()):
            ts = test_stats[pm_id]
            values = ts["values"]
            exec_cnt = len(values) if values else device_count
            tmin = min(values) if values else 0.0
            tmax = max(values) if values else 0.0
            tavg = (sum(values) / len(values)) if values else 0.0
            test_attrs = self._attrs([
                ("Site", ts["site"]),
                ("Head", ts["head"]),
                ("PmId", str(pm_id)),
                ("ExecutionCount", str(exec_cnt)),
                ("FailCount", str(ts["fail_count"])),
                ("TestMinValue", str(tmin)),
                ("TestMaxValue", str(tmax)),
                ("TestAvgTime", str(tavg)),
                ("TestSumValue", str(sum(values)) if values else "0.0"),
                ("TestSumSqrValue", str(sum(v * v for v in values)) if values else "0.0"),
            ])
            lines.append(f"<Test {test_attrs}></Test>")
        lines.append("</TestInfo>")
        lines.append("</SummaryData>")
        return lines

    def _parametric_lines(self, wafer, tests):
        lines = ["<ParametricData>"]
        part_index = 0
        for die in wafer.dies:
            if getattr(die, "inked", None) or getattr(die, "notest", None):
                continue
            part_index += 1
            test_time = ""
            if die.result and len(tests) > 0:
                for i, test in enumerate(tests):
                    if getattr(test, "number", None) == "0.1" and i < len(die.result):
                        test_time = die.result[i]
                        break

            unit_attrs = self._attrs([
                ("Site", str(getattr(die, "site", "0"))),
                ("Head", "1"),
                ("PartId", str(getattr(die, "partid", part_index))),
                ("PartIndex", str(part_index)),
                ("X", str(getattr(die, "x", ""))),
                ("Y", str(getattr(die, "y", ""))),
                ("HardBin", str(getattr(die, "hard_bin", ""))),
                ("SoftBin", str(getattr(die, "soft_bin", ""))),
                ("TestCount", str(len(tests))),
                ("TestTime", test_time),
                ("TouchdownNum", str(getattr(die, "touchdown_num", ""))),
            ])
            ecid = getattr(die, "ecid", None)
            if ecid and self._esc(ecid):
                unit_attrs = f'{unit_attrs} Ecid="{self._esc(ecid)}"'.strip()

            lines.append(f"<Unit {unit_attrs}>")
            for i, test in enumerate(tests):
                pm_id = i + 1
                raw = die.result[i] if i < len(die.result) else "NA"
                meas_attrs = self._attrs([
                    ("PmId", str(pm_id)),
                    ("Val", Util.rep_na(str(raw))),
                    ("PF", self._meas_pf(raw, test)),
                ])
                lines.append(f"<Meas {meas_attrs}></Meas>")
            lines.append("</Unit>")
        lines.append("</ParametricData>")
        return lines

    def build_xml_lines(self, site=None):
        del site  # structure is site-agnostic; ecid already on dies when parsed
        model = self.model
        header = model.header
        wafer = model.wafers[0] if model.wafers else None
        tests = wafer.tests if wafer else []

        lines = ['<?xml version="1.0" encoding="ISO-8859-1"?>', "<Xml>"]

        file_attrs = self._attrs([
            ("FileName", self.input_filename),
            ("CPUType", "2"),
            ("STDFVersion", "4"),
        ])
        lines.append(f"<File {file_attrs}>")
        lines.extend(self._metadata_lines())

        lot_attrs = self._attrs([
            ("LotId", getattr(header, "LOT", "")),
            ("PartType", getattr(header, "PRODUCT", "")),
            ("JobName", getattr(header, "PROGRAM", "")),
            ("JobRevision", getattr(header, "REVISION", "")),
            ("OperatorName", getattr(header, "OPERATOR", "")),
            ("NodeName", getattr(header, "EQUIP1_ID", "")),
            ("TesterType", "EAGLE"),
            ("ExecType", "EAGLE"),
            ("ExecVersion", getattr(header, "REVISION", "")),
            ("FacilityId", getattr(header, "EQUIP6_ID", "")),
            ("FloorId", getattr(header, "EQUIP6_ID", "")),
            ("FamilyId", getattr(header, "FAMILY", "")),
            ("ProcessId", getattr(header, "PROCESS", "")),
            ("PackageType", getattr(header, "PACKAGE", "")),
            ("TestCode", getattr(header, "STEP", "")),
            ("ModeCode", "P"),
            ("RetestCode", "N"),
            ("SublotId", str(getattr(wafer, "number", "")) if wafer else ""),
            ("SetupTime", getattr(wafer, "START_TIME", "") if wafer else ""),
            ("StartTime", getattr(wafer, "START_TIME", "") if wafer else ""),
            ("FinishTime", getattr(wafer, "END_TIME", "") if wafer else ""),
            ("StationNumber", "1"),
            ("UserText", getattr(header, "INDEX1", "")),
            ("AUXFile", getattr(header, "INDEX2", "")),
            ("LoadBoardId", getattr(header, "EQUIP4_ID", "")),
            ("CardId", getattr(header, "EQUIP3_ID", "")),
            ("HandlerId", getattr(header, "EQUIP5_ID", "")),
            ("TesterSerial", getattr(header, "EQUIP2_ID", "")),
        ])
        lines.append(f"<Lot {lot_attrs}>")

        lines.extend(self._wmc_lines())
        if wafer:
            lines.extend(self._sites_lines(wafer))
        lines.extend(self._parameters_lines(tests))
        if wafer:
            lines.extend(self._summary_lines(wafer, tests))
            lines.extend(self._parametric_lines(wafer, tests))

        lines.append("</Lot>")
        lines.append("</File>")
        lines.append("</Xml>")
        return lines

    def build_xml_string(self, site=None):
        return "".join(self.build_xml_lines(site=site))
