#!/usr/bin/env bash
set -euo pipefail

SOURCE_DB="OSV"
START_HOURS=32
END_HOURS=12

DPLOG="${DPLOG:-/apps/exensio_data/log}"
DPDATA="${DPDATA:-/apps/exensio_data}"

LOG_FILE="${DPLOG}/getCamstarWafer2AssemblyGenealogy.${SOURCE_DB}.$(date +"%Y%m%d_%H%M%S").log"

OUT_GEN="${DPDATA}/cloudsite-upload/genealogy_nofilter/PRODUCTION"
ARCHIVE_GEN="${DPDATA}/archives-yms/reference_data/assembly_trace_archive"
OUT_TRACE="${DPDATA}/data/assembly_trace"
ARCHIVE_TRACE="${DPDATA}/archives-yms/reference_data/assembly_trace"

SOURCES_JSON=$(cat <<JSON
{
  "sources": [
    {
      "name": "${SOURCE_DB}",
      "source_odbc": "MSSQL-${SOURCE_DB}",
      "snow_user": "READ_ONLY_REPORTS",
      "snow_password": "REPLACE_WITH_PASSWORD",
      "params": {
        "start_hours": ${START_HOURS},
        "end_hours": ${END_HOURS}
      },
      "outputs": [
        {
          "name": "genealogy",
          "sql_file": "REPLACE_WITH_SQL_GENEALOGY_FILE",
          "output_prefix": "CamstarWafer2AssemblyGenealogy",
          "reference_data_dir": "${OUT_GEN}",
          "archive_dir": "${ARCHIVE_GEN}",
          "header": null
        },
        {
          "name": "trace",
          "sql_file": "REPLACE_WITH_SQL_TRACE_FILE",
          "output_prefix": "CamstarAssemblyTrace",
          "reference_data_dir": "${OUT_TRACE}",
          "archive_dir": "${ARCHIVE_TRACE}",
          "header": "LOT|ASSEMBLY_PART_COUNT|SOURCE_LOT|LOT_TYPE|PRODUCT|CONSUMPTION_DATE|FROM_PRODUCT|FROM_EXENSIO_SOURCE_LOT|FROM_EXENSIO_WAFER_ID|FROM_WAFER_NUMBER|FROM_FAB|FROM_INVENTORY_LOT|FROM_WAFER_SCRIBE|QTY_CONSUMED|QTY_REQUIRED|CONSUME_FACTOR|MATERIAL_LOT|ASSEMBLY_STEP"
        }
      ]
    }
  ]
}
JSON
)

python "$(dirname "$0")/refdata_extract.py" \
  --sources_json "$SOURCES_JSON" \
  --log_dir "$DPLOG" \
  --log_file "$(basename "$LOG_FILE")"
