"""Test limit parameter validation and OpenAPI schema for GET /get_pipeline_info endpoint."""

from fastapi.testclient import TestClient
import sys
from pathlib import Path

# Ensure repo root is on sys.path so imports like `import main` work under pytest
repo_root = str(Path(__file__).resolve().parents[1])
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)

from main import api_app as app

client = TestClient(app)


def test_openapi_limit_max_10000():
    """Assert OpenAPI param for limit has maximum 10000."""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    
    openapi_spec = response.json()
    
    # Navigate to the get_pipeline_info endpoint parameter definition
    paths = openapi_spec.get("paths", {})
    get_pipeline_info = paths.get("/get_pipeline_info", {})
    get_method = get_pipeline_info.get("get", {})
    parameters = get_method.get("parameters", [])
    
    # Find the limit parameter
    limit_param = None
    for param in parameters:
        if param.get("name") == "limit":
            limit_param = param
            break
    
    assert limit_param is not None, "limit parameter not found in OpenAPI spec"
    
    # Check the parameter schema has maximum 10000
    schema = limit_param.get("schema", {})
    assert "maximum" in schema, "limit parameter should have maximum constraint"
    assert schema["maximum"] == 10000, f"Expected maximum 10000, got {schema['maximum']}"


def test_rejects_above_max():
    """GET /get_pipeline_info?limit=10001 returns 422."""
    response = client.get("/get_pipeline_info?limit=10001")
    assert response.status_code == 422
    
    # Verify it's a validation error
    error_detail = response.json()
    assert "detail" in error_detail
    # FastAPI returns validation errors in a specific format
    details = error_detail["detail"]
    assert any("limit" in str(detail) for detail in details), "Error should mention limit parameter"


def test_accepts_10000_not_422():
    """GET /get_pipeline_info?limit=10000 returns a status code != 422."""
    response = client.get("/get_pipeline_info?limit=10000")
    
    # Should not be a validation error (422)
    assert response.status_code != 422
    
    # Status code may be 200, 404, or 500 depending on backend availability
    # but it should not be 422 (validation error)
    assert response.status_code in [200, 404, 500], f"Unexpected status code: {response.status_code}"