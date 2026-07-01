"""pipeline-service app package

Provides a simple package marker so test runners and older Pythons reliably
import `app.*` modules during test collection.
"""
__all__ = ["utils", "models", "repository", "parsers"]
