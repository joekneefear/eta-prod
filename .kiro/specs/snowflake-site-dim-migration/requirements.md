# Requirements Document

## Introduction

This specification defines the requirements for migrating the SITE_DIM data source from Oracle Data Warehouse to Snowflake in the getDWProductMetadata.sh script. The script currently queries BIWMARTS.SITE_DIM from Oracle to retrieve manufacturing area descriptions (MFG_AREA_DESC) based on MFG_AREA_CD and FE_BE_FLG. The migration will replace the Oracle SITE_DIM source with Snowflake as the sole source for this reference data.

## Glossary

- **SITE_DIM**: Site dimension table containing manufacturing area codes and descriptions
- **MFG_AREA_CD**: Manufacturing area code (e.g., 'UWA', 'BK', 'CP')
- **MFG_AREA_DESC**: Manufacturing area description (human-readable name)
- **FE_BE_FLG**: Front-end/Back-end flag
- **CTE**: Common Table Expression (SQL WITH clause)
- **Oracle_DW**: Oracle Data Warehouse (current source)
- **Snowflake**: Cloud data warehouse (target source)
- **getDWProductMetadata_Script**: The bash script that extracts product reference data
- **ODBC**: Open Database Connectivity interface for database access

## Requirements

### Requirement 1: Snowflake Connection Configuration

**User Story:** As a data engineer, I want to configure Snowflake connection parameters, so that the script can connect to Snowflake to retrieve SITE_DIM data.

#### Acceptance Criteria

1. WHEN Snowflake connection parameters are provided as command-line arguments, THE getDWProductMetadata_Script SHALL accept and validate them
2. WHEN the Snowflake warehouse parameter is provided, THE getDWProductMetadata_Script SHALL use the value 'MFG_PRD_RPT_WH'
3. WHEN the Snowflake schema parameter is provided, THE getDWProductMetadata_Script SHALL use the value 'ANALYTICSPRD.MFG'
4. WHEN the Snowflake ODBC source is provided, THE getDWProductMetadata_Script SHALL use the value 'MART_SNOWFLAKE'
5. WHEN Snowflake parameters are missing or invalid, THE getDWProductMetadata_Script SHALL exit with an error message

### Requirement 2: SITE_DIM Data Extraction from Snowflake

**User Story:** As a data engineer, I want to extract SITE_DIM data from Snowflake, so that the script uses the current reference data source.

#### Acceptance Criteria

1. THE getDWProductMetadata_Script SHALL query SITE_DIM table from Snowflake schema 'ANALYTICSPRD.MFG.SITE_DIM'
2. WHEN querying Snowflake SITE_DIM, THE getDWProductMetadata_Script SHALL retrieve MFG_AREA_CD, MFG_AREA_DESC, and FE_BE_FLG columns
3. WHEN Snowflake query completes successfully, THE getDWProductMetadata_Script SHALL store SITE_DIM data in a pipe-delimited temporary file
4. WHEN Snowflake query fails, THE getDWProductMetadata_Script SHALL exit with an error message
5. THE getDWProductMetadata_Script SHALL use a separate query tool (Python or Perl with ODBC) to extract SITE_DIM from Snowflake before running the main Oracle query

### Requirement 3: Hybrid Query Construction with Oracle External Table

**User Story:** As a data engineer, I want the script to construct SQL queries that use Snowflake SITE_DIM data with Oracle DW data, so that I can leverage both data sources efficiently.

#### Acceptance Criteria

1. THE getDWProductMetadata_Script SHALL create an Oracle external table definition that reads the Snowflake SITE_DIM temporary file
2. WHEN constructing the main SQL query, THE getDWProductMetadata_Script SHALL replace BIWMARTS.SITE_DIM references with the external SITE_DIM table
3. WHEN the external SITE_DIM table is used, THE getDWProductMetadata_Script SHALL maintain the same join conditions (MFG_AREA_CD and FE_BE_FLG)
4. WHEN the query completes, THE getDWProductMetadata_Script SHALL drop the external table definition
5. THE getDWProductMetadata_Script SHALL produce identical output format regardless of the SITE_DIM source change

### Requirement 4: Error Handling

**User Story:** As a system administrator, I want clear error messages when Snowflake connection fails, so that I can troubleshoot issues quickly.

#### Acceptance Criteria

1. WHEN Snowflake connection fails, THE getDWProductMetadata_Script SHALL exit with a non-zero exit code
2. WHEN Snowflake query fails, THE getDWProductMetadata_Script SHALL display the error message to stderr
3. WHEN SITE_DIM data cannot be retrieved, THE getDWProductMetadata_Script SHALL log the failure reason
4. WHEN temporary table creation fails, THE getDWProductMetadata_Script SHALL exit with an error message
5. WHEN the script exits due to error, THE getDWProductMetadata_Script SHALL clean up any temporary files or tables created

### Requirement 5: Logging and Monitoring

**User Story:** As a data engineer, I want detailed logging of Snowflake data retrieval, so that I can troubleshoot issues and monitor the migration.

#### Acceptance Criteria

1. WHEN the script starts, THE getDWProductMetadata_Script SHALL log that SITE_DIM will be retrieved from Snowflake
2. WHEN Snowflake query executes, THE getDWProductMetadata_Script SHALL log the query execution time
3. WHEN Snowflake query fails, THE getDWProductMetadata_Script SHALL log the error message
4. WHEN SITE_DIM data is loaded, THE getDWProductMetadata_Script SHALL log the number of rows retrieved
5. WHEN the script completes, THE getDWProductMetadata_Script SHALL log the total execution time

### Requirement 6: Data Validation

**User Story:** As a data engineer, I want to validate that Snowflake SITE_DIM data is compatible with the Oracle query, so that results remain accurate.

#### Acceptance Criteria

1. WHEN SITE_DIM data is retrieved from Snowflake, THE getDWProductMetadata_Script SHALL verify that required columns exist (MFG_AREA_CD, MFG_AREA_DESC, FE_BE_FLG)
2. WHEN SITE_DIM data contains null values in key columns, THE getDWProductMetadata_Script SHALL log a warning
3. WHEN SITE_DIM row count is zero, THE getDWProductMetadata_Script SHALL log an error and exit
4. WHEN SITE_DIM data format is incompatible, THE getDWProductMetadata_Script SHALL exit with an error message
5. WHEN validation passes, THE getDWProductMetadata_Script SHALL proceed with the hybrid query
