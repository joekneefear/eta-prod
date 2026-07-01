# Pipeline Service Study Guide

A comprehensive guide for designing, developing, operating, and evolving the FastAPI-based pipeline metadata service contained in this repository.

## 1. Purpose & Scope
The service ingests and serves metadata about data pipeline executions. It supports multi-backend persistence (JSONL for lightweight/local use, Oracle for production). This guide covers architecture, design decisions, best practices, and enhancement paths.

## 2. High-Level Architecture
- **Clients / UI**: Frontend, CLI, or scripts consume REST endpoints.
- **API Layer (FastAPI)**: Request validation, routing, serialization.
- **Repository Abstraction**: `PipelineInfoRepository` interface to decouple storage.
- **Persistence Backends**:
  - `JsonlPipelineRepository`: File-based append-only JSON Lines.
  - `OraclePipelineRepository`: Relational storage using `python-oracledb`.
- **Models**: Pydantic v2 models (`PipelineInfo`, `PipelineSummary`, response wrappers).

Key advantages: loose coupling, easier backend swapping, testability, consistent API contract.

## 3. Data & Domain Modeling
### Core Entity: `PipelineInfo`
Represents one pipeline run with timestamps, metrics, artifacts, classification fields.

Important field categories:
- Temporal: `start_local`, `end_local`, `start_utc`, `end_utc`, `elapsed_seconds`, `elapsed_human`.
- Operational Metrics: `rowcount`, `pid`.
- Identifiers: `date_code`, optional classification (`pipeline_name`, `script_name`, `pipeline_type`, `environment`).
- Artifacts: `output_file`, `log_file`.

### Aggregation: `PipelineSummary`
Provides statistical overview (totals, averages, last run) grouped by pipeline signature.

### Modeling Principles
- Use native `datetime` for computation; convert to ISO 8601 for serialization.
- Keep averages optional (null when no runs with positive metrics).
- Allow optional classification fields to ease incremental adoption.

## 4. Repository Pattern
Interface methods:
- `get_pipeline_info(...)` – filtered retrieval with pagination.
- `count_pipeline_info(...)` – cardinality for pagination or summary.
- `get_pipelines_summary()` – aggregated stats.
- `insert_pipeline_info(record)` – ingestion.

### JSONL Implementation
- Simplicity: Append new lines; read-then-filter for queries.
- Limitations: O(N) scans, no concurrency guarantees, potential file growth issues.
- Mitigations: file rotation, locking, eventual migration to an embedded DB.

### Oracle Implementation
- Uses dynamic SQL WHERE assembly with parameter binding.
- Supports optional column name mapping (`ORACLE_COLUMN_MAP`) to adapt to existing schemas.
- Paging via ROWNUM window; can be upgraded to keyset pagination.

## 5. API Design
Endpoints (core):
- `GET /pipelines` — aggregated summaries.
- `GET /get_pipeline_info` — filtered runs with pagination.
- `POST /pipelines` — insert a run.
- `GET /health` — liveness probe.

Design principles:
- Explicit query params for filters (discoverable in OpenAPI docs).
- Safe pagination (limit bounds 1–10000).
- Optional `all_data` flag for full export (consider server limits to prevent abuse).

Potential addition: `/download/pipeline_info` for direct CSV/JSONL export (see Enhancements).

## 6. Validation & Serialization
- Pydantic handles type coercion, datetime parsing, schema generation.
- Use `model_dump()` for persistence; convert datetimes to ISO only when targeting JSON serialization or line-based output.
- Future: custom validators (e.g., ensure `end_utc >= start_utc`).

## 7. Filtering & Pagination Strategy
- Filtering occurs either in memory (JSONL) or via SQL predicates (Oracle).
- Consistency: ensure both backends implement the same semantics.
- Scaling concern: offset pagination can degrade with large offsets; consider keyset pagination for Oracle (e.g., `WHERE start_utc < :cursor` ORDER BY start_utc DESC LIMIT N pattern using analytic functions or `FETCH FIRST`).

## 8. Oracle (python-oracledb) Considerations
- Thin mode currently (pure Python). Thick mode offers advanced features if Oracle Client libraries are installed.
- Introduce connection pooling: `oracledb.create_pool(...)` and reuse across requests for performance.
- Index Strategy:
  - Composite index `(pipeline_name, start_utc)` for common queries.
  - Individual indexes on `pipeline_type`, `environment` if selective.
  - Partitioning by date for large historical datasets.
- Use binds to avoid SQL injection and improve plan caching.

## 9. JSONL Backend Considerations
- Suitable for local development and small datasets (< a few MBs).
- No schema enforcement beyond model parsing at read time (corrupt lines skipped with warnings).
- Evolution strategy: periodic compaction; convert large files to a DB table offline.

## 10. Error Handling & Resilience
- Map domain errors to HTTP codes: validation (400), missing resources (404), server/internal (500).
- Log unexpected exceptions with stack trace (but sanitize sensitive info).
- Potential resilience enhancements: retry transient DB errors, circuit breaker for repeated failures.

## 11. Security
- Current: no authentication (appropriate only for internal/trusted environments).
- Roadmap:
  1. API key or token-based auth for POST endpoints.
  2. OAuth2/JWT for fine-grained control.
  3. RBAC or attribute-based authorization per environment (prod vs dev access).
- Guardrails: validate `ORACLE_COLUMN_MAP` to only allow safe column identifiers (alphanumeric & underscore).
- Secrets management: environment variables + secret manager (avoid embedding creds in code/images).

## 12. Observability
- **Logging**: Structured (JSON) with fields: timestamp, level, endpoint, latency_ms, error_code.
- **Metrics**: Request latency, count, error counts, DB query time, insert throughput (Prometheus exporters).
- **Tracing**: OpenTelemetry instrumentation for request spans + DB spans.
- **Dashboards**: Latency percentiles, error ratios, pipeline volume trends.

## 13. Testing Strategy
- **Unit Tests**: Filtering logic, column mapping, serialization edge cases.
- **Integration Tests**: API endpoints using FastAPI TestClient & ephemeral JSONL file.
- **Oracle Tests**: Use a mock or a containerized Oracle XE; separate test marker (e.g., `@pytest.mark.oracle`).
- **Property Testing**: Validate monotonicity (loosening filters cannot reduce result set size).
- **Performance Smoke**: Basic load (k6/locust) for `get_pipeline_info` under typical concurrency.

## 14. Performance & Scaling
- JSONL backend becomes a bottleneck quickly—promote to Oracle or another RDBMS.
- Add caching for common queries (in-memory TTL or Redis) for summaries.
- Introduce streaming exports for large downloads (yield row-by-row) instead of holding everything in memory.
- Optimize serialization: use `orjson` response class for large payloads.

## 15. Deployment & Operations
- Containerize using multi-stage Dockerfile; run with Uvicorn or Gunicorn workers.
- Use readiness (`/health`) for orchestration probes.
- Horizontal scaling: Each replica uses its own repository instance (stateless). Ensure DB pool size sum across replicas is within DB limits.
- CI/CD pipeline: lint → tests → build → scan → deploy staging → integration tests → promote.
- Observability integration at deployment time (env vars for OTEL exporters, Prometheus scraping).

## 16. Migration: cx_Oracle → python-oracledb
- Unified driver replacing legacy `cx_Oracle`.
- API mostly compatible; prefer explicit parameter names in `connect`.
- Plan to add connection pool to reduce per-request connect cost.

## 17. Enhancements Roadmap
| Priority | Enhancement | Benefit |
|----------|-------------|---------|
| High | Connection pooling for Oracle | Lower latency, resource efficiency |
| High | Auth (API key/JWT) | Secure write operations |
| Medium | Download/export endpoint (CSV/JSONL) | Usability, data analysis |
| Medium | Keyset pagination | Performance on large datasets |
| Medium | Metrics + tracing | Observability & debugging |
| Medium | Enum validation for `pipeline_type`, `environment` | Data quality |
| Low | Bulk insert endpoint | Ingestion efficiency |
| Low | Caching summaries | Lower DB load |
| Low | UI dashboard | Insight, stakeholder access |

## 18. Operational Runbook (Quick Reference)
| Scenario | Action |
|----------|--------|
| Failing DB connections | Verify creds/env vars, test `tnsping`/network, check DB listener |
| Slow queries | Examine execution plan, add indexes, verify stats |
| High 5xx error rate | Inspect logs for common exception, check DB pool exhaustion |
| Large JSONL file | Rotate & archive; schedule migration to DB |
| Schema change needed | Add nullable column → backfill → enforce NOT NULL → update mapping |

## 19. Security Hardening Phases
1. Introduce API key header (e.g., `X-API-Key`).
2. Move to OAuth2 password or client-credentials grant.
3. Attribute-based restrictions (prod-only accessible for certain roles).
4. Audit logging for inserts & updates.

## 20. Code Quality & Maintenance
- Use consistent formatting (black/ruff) & type checking (mypy) for early detection.
- Enforce commit hooks for lint/tests before push.
- Keep dependencies updated; monitor vulnerabilities (e.g., `pip-audit`).

## 21. Future Backend Options
- PostgreSQL (async: `asyncpg`) with materialized views for summaries.
- DuckDB/Parquet for analytics workloads.
- Elasticsearch/OpenSearch for flexible text & filter queries.
- Redis (temporary cache) for recent runs.

## 22. Implementation Checklist for Key Features
### Add Connection Pooling (Oracle)
- Create global pool at startup.
- Replace direct `connect()` calls with `pool.acquire()` context.
- Add metrics: pool in-use vs free.

### Add Export Endpoint
- Implement streaming generator (CSV/JSONL) using `StreamingResponse`.
- Validate `format` query param.
- Set `Content-Disposition` for browser download.

### Add Auth (API Key)
- Add dependency that reads header; compare against env var secret.
- Apply only to POST insertion first.

### Add Metrics
- Use `prometheus_client` or `prometheus-fastapi-instrumentator`.
- Expose `/metrics`.

## 23. Learning Path
1. FastAPI core features.
2. Pydantic v2 advanced usage.
3. Repository & Unit of Work patterns.
4. Oracle driver specifics (pooling, binds, performance tuning).
5. Observability stack (Prometheus, OpenTelemetry).
6. Security protocols (JWT/OAuth2 flows).
7. Scalability strategies (caching, pagination optimization). 

## 24. Reference Commands
```bash
# Run development server
uvicorn main:app --reload --port 8000

# Install Oracle driver
pip install python-oracledb

# Run tests
pytest -q
```

## 25. Glossary
- **JSONL**: Newline-delimited JSON; each line a standalone JSON object.
- **Keyset Pagination**: Pagination based on the last seen key rather than offset for performance.
- **Thin/Thick Mode**: python-oracledb operating modes (pure Python vs with Oracle Client libs).
- **TTL Cache**: Time-limited cache entry expiration strategy.

---
*End of Guide.*
