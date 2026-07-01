"""Parser registry for pipeline-service.

Provides `get_parser(script_name, pipeline_name)` to select an appropriate
parser implementation for structured metadata extraction.
"""
from .e142_parser import E142Parser

def get_parser(script_name: str = None, pipeline_name: str = None):
    """Return a parser instance appropriate for the given script or pipeline.

    Simple heuristic matching for now; extend with entrypoints/plugins later.
    """
    s = (script_name or "").lower()
    p = (pipeline_name or "").lower()

    # E142 variants (script name contains 'e142' or 'snowflakee142' etc.)
    if "e142" in s or "e142" in p or "snowflakee142" in s:
        return E142Parser()

    # Default: no-op parser (None)
    return None
