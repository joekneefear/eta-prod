# Plan: BK WorkStream Lookup Service Integration

Integrate the BK-specific lot lookup retry logic into the Klarf 1.8 Enrichment pipeline. This ensures that lots at the BK site can be correctly enriched even if the generic lookup fails.

## Proposed Changes

### Configuration
#### [MODIFY] [Klarf18_Enrichment.yaml](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15\eta_master\scripts\py\resources\Klarf18_Enrichment.yaml)
- Add `ws_site_retry: "BK"` to the `BK_SICA88_Rework` section to enable the site-specific retry.

---

### Enrichment Logic
#### [MODIFY] [klarf_18_enricher.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/klarf_18_enricher.py)
- Move the `FabID` extraction and site detection logic earlier in [main()](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/klarf_18_enricher.py#55-408) (before the ERT API metadata fetch).
- Implement a retry mechanism in the ERT API metadata fetch section:
    - If the first lookup results in `NO_DATA`.
    - AND the resolved `site_config` contains a `ws_site_retry` property.
    - Then retry the lookup with `?site={ws_site_retry}` appended to the request URL.

---

## Verification Plan

### Automated Tests
- Create a test script `tests/test_bk_retry.py` that:
    - Mocks the `RefdbAPIClient.get_metadata` method.
    - Simulates a first call returning `{"status": "NO_DATA"}`.
    - Simulates a second call with `?site=BK` returning valid metadata.
    - Verifies that [klarf_18_enricher.py](file:///c:/Users/fg8n8x/Desktop/eta/eta_1_15/eta_master/scripts/py/klarf_18_enricher.py) uses the second response and correctly routes to `PRODUCTION`.

### Manual Verification
1. Run the script with a known BK lot and `--pplog` enabled:
   ```bash
   python scripts/py/klarf_18_enricher.py --infile tests/test_bk_lot.klarf --out output/ --ws_url scripts/py/lib/WS/url.yaml --ws_source prod
   ```
2. Verify in the log file (`DPLOG/klarf_18_enricher.log`) that the retry logic was triggered and succeeded.
3. Confirm that the output file is written to the `PRODUCTION` subdirectory.
