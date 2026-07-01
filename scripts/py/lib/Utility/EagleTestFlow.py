"""
Test flow code lookup (port of PDF::Util::AddTestFlowtoTPUsingRef).
"""

import os
import re
from lib.Log import Log


TF_SITES = {
    "gtk_tw_ft", "hana_th_ft", "atec_ph_ft", "isti_tw_csp", "its_tw_ft",
    "amkor_tw_csp", "etrend_tw_ft", "utac_th_ft", "amkor_ph_ft",
}


def load_testflow_ref(site, ref_file):
    test_flow = {}
    retest_code = {}
    tf_sbox = []
    tf_prod = []
    site_key = site.replace("_", "").lower()
    current = False
    if not ref_file or not os.path.isfile(ref_file):
        return test_flow, retest_code, tf_sbox, tf_prod
    with open(ref_file, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.upper().strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("SITE") and "=" in line:
                normalized = line.replace("_", "").replace(" ", "").lower()
                current = site_key in normalized
                continue
            if "," in line and current:
                parts = line.split(",")
                if len(parts) < 4:
                    continue
                tf_code, append, rw_code, load = [p.strip() for p in parts[:4]]
                if not tf_code or not append:
                    continue
                test_flow[tf_code] = append
                retest_code[tf_code] = rw_code
                if "SANDBOX" in load:
                    tf_sbox.append(tf_code)
                if "PRODUCTION" in load:
                    tf_prod.append(tf_code)
    return test_flow, retest_code, tf_sbox, tf_prod


def add_test_flow_to_tp(model, test_mode, site, ref_file):
    if site not in TF_SITES:
        return ""
    test_flow, retest_code, tf_sbox, tf_prod = load_testflow_ref(site, ref_file)
    header = model.header
    test_mode = (test_mode or "").strip().upper()
    tf_mode = test_flow.get(test_mode, "")
    if tf_mode in tf_sbox:
        model.forSBflag = 1
        Log.WARN(f"Loaded to Sandbox due to test mode = {tf_mode}")
    elif tf_mode not in tf_prod:
        if site == "amkor_tw_csp" and test_mode == "":
            pass
        else:
            Log.WARN(f"Unknown test mode = {test_mode}")
            model.forSBflag = 1
    if test_mode in retest_code:
        header.INDEX2 = retest_code[test_mode]
    Log.INFO(f"Appended Test Code to Program = {tf_mode}")
    return tf_mode
