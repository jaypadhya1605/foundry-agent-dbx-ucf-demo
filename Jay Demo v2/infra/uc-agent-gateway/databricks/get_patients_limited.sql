-- Run in the BrakeKat workspace SQL editor (warehouse adb-demo-wh) as jay@brakekat.com, or via
-- Setup-DatabricksSide.ps1. Adds only the UC-side row cap. The table, filters and masks already exist.
-- Names are fully qualified because the script sends each statement as its own API call, so USE CATALOG does not carry over.

CREATE OR REPLACE FUNCTION imh_demo.clinical.get_patients_limited(
  fac      STRING DEFAULT NULL COMMENT 'Facility code, e.g. SLC. NULL = all facilities the caller may see.',
  max_rows INT    DEFAULT 5    COMMENT 'Rows to return (1-10). Larger values are capped at 10.')
RETURNS TABLE (patient_id STRING, name STRING, ssn STRING, facility STRING, diagnosis STRING)
COMMENT 'Like get_patients, but Unity Catalog caps the result at 10 rows. Filters and masks still apply.'
RETURN
  SELECT patient_id, name, ssn, facility, diagnosis
  FROM (
    SELECT patient_id, name, ssn, facility, diagnosis,
           row_number() OVER (ORDER BY patient_id) AS rn
    FROM imh_demo.clinical.patients
    WHERE fac IS NULL OR facility = upper(fac)
  )
  -- Filter in WHERE: Databricks cannot resolve function parameters inside QUALIFY.
  WHERE rn <= least(greatest(coalesce(max_rows, 5), 1), 10);

-- Schema-level EXECUTE already covers new functions; explicit grants keep it obvious in Catalog Explorer.
GRANT EXECUTE ON FUNCTION imh_demo.clinical.get_patients_limited TO `imh_analyst`;
GRANT EXECUTE ON FUNCTION imh_demo.clinical.get_patients_limited TO `imh_clinician_slc`;
GRANT EXECUTE ON FUNCTION imh_demo.clinical.get_patients_limited TO `imh_phi_full`;

-- Proof queries
SELECT count(*) AS rows_default FROM imh_demo.clinical.get_patients_limited();          -- 5
SELECT count(*) AS rows_capped  FROM imh_demo.clinical.get_patients_limited(NULL, 50);  -- 10, not 12
