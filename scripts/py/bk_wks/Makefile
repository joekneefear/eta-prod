.PHONY: help install install-dev clean test type-check format lint check

help:
	@echo "Scribe-Lot-Mapper Development Commands"
	@echo ""
	@echo "  make install          Install package in production mode"
	@echo "  make install-dev      Install package with dev dependencies"
	@echo "  make test             Run all tests with coverage"
	@echo "  make test-unit        Run unit tests only"
	@echo "  make test-property    Run property-based tests only"
	@echo "  make test-integration Run integration tests only"
	@echo "  make type-check       Run mypy type checking (strict mode)"
	@echo "  make format           Format code with black"
	@echo "  make lint             Run ruff linter"
	@echo "  make check            Run all checks (type, format, lint)"
	@echo "  make clean            Remove build artifacts and cache files"

install:
	pip install -e .

install-dev:
	pip install -e ".[dev]"

test:
	pytest tests/ --cov=scribe_lot_mapper --cov-report=html --cov-report=term-missing -v

test-unit:
	pytest tests/unit/ -v

test-property:
	pytest tests/property_based/ -v

test-integration:
	pytest tests/integration/ -v

type-check:
	mypy src/scribe_lot_mapper/ --strict

format:
	black src/scribe_lot_mapper/ tests/

lint:
	ruff check src/scribe_lot_mapper/ tests/ --fix

check: type-check lint format test

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".coverage" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "htmlcov" -exec rm -rf {} + 2>/dev/null || true
	rm -rf build/ dist/ .eggs/
