# Architecture and Implementation Patterns

## Overview
This document outlines the architectural patterns, design choices, and implementation techniques used in the **SHEDCL DTS1000/DTS2000 (JUNO)** parser and translator project.

---

## 1. Architectural Patterns

### 1.1 Translator-Enricher Pattern
The main script (`dts1000_juno_translator_enricher.py`) follows the standard **Translator-Enricher** pattern used across the ETa framework:

1.  **Translate**: Convert raw vendor-specific format (Excel) into a standardized internal model (`lib.Data.Model`).
2.  **Enrich**: Augment the model with metadata from external systems (RefDB) using `refdb_lookup`.
3.  **Format**: Serialize the enriched model into the target output format (IFF).

**Benefits**: Decouples input format parsing from output generation and business logic.

### 1.2 Strategy Pattern (Custom Extraction)
To handle site-specific variations without modifying the core parser, we implemented the **Strategy Pattern** via the `ParserConfig` and `CustomExtractors` modules.

*   **Context**: `Dts1k2kXlsParser` needs to extract fields like Lot ID, but the format varies.
*   **Strategy Interface**: Defined by the `extract(raw_data, context)` signature.
*   **Concrete Strategies**: `LotIdExtractor`, `TestProgramExtractor`, `DataportTimeExtractor`.
*   **Configuration**: `ParserConfig` acts as the strategy factory/registrar, loading rules from `resources/dts1000_custom_parsers.yaml`.

**Benefits**: Follows the *Open/Closed Principle*—open for extension (new extractors), closed for modification (core parser logic).

### 1.3 Configuration-as-Code (YAML)
Site-specific parsing rules are externalized into YAML configuration files (`dts1000_custom_parsers.yaml`) instead of being hardcoded.

**Benefits**:
*   Allows non-developers to adjust parsing rules.
*   Supporting multiple sites (PHXFT, SITE2) with a single codebase.
*   Enables "Zero-code" updates for regex pattern changes.

---

## 2. Implementation Techniques

### 2.1 Hybrid File Loading (Performance Optimization)
The parser uses a **hybrid loading strategy** to optimize performance based on the specific file format:

*   **`.xls` (Legacy Excel)**: Uses `xlrd`.
    *   *Why*: `xlrd` is 3-5x faster than `openpyxl` for legacy binary Excel files.
*   **`.xlsx` (Modern Excel)**: Uses `openpyxl` in `read_only=True` mode.
    *   *Why*: `read_only` mode minimizes memory usage by streaming data instead of loading the entire DOM.
*   **`.csv` (Text)**: Uses `pandas` (with `csv` module fallback).
    *   *Why*: `pandas` C-optimized engine is significantly faster for large text files.

**Method**: `_load_file_optimized(infile)` in `Dts1k2kXlsParser`.

### 2.2 Compiled Regular Expressions
All regex patterns are compiled at the class level (`_PATTERNS` dictionary) rather than being re-compiled inside loops.

**Benefits**:
*   Reduces overhead during row-by-row parsing.
*   Centralizes pattern definitions for easier maintenance.

### 2.3 Dependency Injection
Dependencies like `config` and `pplogger` are injected into the `Dts1k2kXlsParser` constructor rather than being instantiated internally or accessed via globals.

**Code Example**:
```python
parser = Dts1k2kXlsParser(config=parser_config, pplogger=pplogger)
```

**Benefits**:
*   Improves testability (easier to mock dependencies).
*   Ensures consistent logging context (main script and parser share the same logger).

### 2.4 Lazy Loading / Caching
The parser caches extractor lookups to avoid repeated dictionary and configuration checks for every row.

**Method**: `_get_extractor(extractor_name)` uses `_extractor_cache`.

### 2.5 Robust Error Handling with PPLogger
The system integrates with `pplogger` (Process Platform Logger) to ensure critical errors are logged to the central database (`refdb.pp_log`) before exiting.

**Pattern**:
```python
if error:
    Util.dp_exit(1, pplogger=self.pplogger, error="Message")
```

---

## 3. Directory Structure & Refactoring

### 3.1 Package Organization
*   `lib.Parser`: Contains the core parsing logic (`Dts1k2kXlsParser.py`).
*   `lib.Config`: Dedicated package for configuration management (`ParserConfig.py`).
*   `lib.Util`: Shared utilities.

**Refactoring**: Moved `ParserConfig` from `lib.Parser` to `lib.Config` to separate concerns (Logic vs. Configuration) and prevent circular dependencies.

---

## 4. Class responsibilities

| Class | Responsibility |
|-------|----------------|
| `Dts1k2kXlsParser` | Orchestrates parsing, manages state (wafer/die/test), handles file I/O. |
| `ParserConfig` | Loads YAML, registers extractors, provides extractor instances. |
| `Model` | Internal data representation (Wafers, Dies, Tests). |
| `Metadata` | Stores header info, standardizes date formats. |
