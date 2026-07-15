"""Base class for output generators.

Provides abstract interface for all output format generators.
"""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import List

from scribe_lot_mapper.models import MappingRecord


class OutputGenerator(ABC):
    """Abstract base class for output generators.

    Defines interface for generating output in different formats.
    """

    def __init__(self, output_dir: str | Path) -> None:
        """Initialize OutputGenerator.

        Args:
            output_dir: Directory for output files
        """
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    @abstractmethod
    def generate(self, records: List[MappingRecord], filename: str) -> None:
        """Generate output file.

        Args:
            records: List of mapping records to output
            filename: Output filename (without directory)
        """
        pass

    @abstractmethod
    def write_headers(self) -> None:
        """Write output headers."""
        pass

    def get_output_path(self, filename: str) -> Path:
        """Get full path for output file.

        Args:
            filename: Output filename

        Returns:
            Path: Full path to output file
        """
        return self.output_dir / filename
