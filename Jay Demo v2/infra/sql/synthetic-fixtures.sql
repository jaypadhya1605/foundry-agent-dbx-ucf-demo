-- Execute only in the approved new workspace as the fixture owner.
-- Do not grant the MCP identity catalog/schema ownership or broad group privileges.
CREATE CATALOG IF NOT EXISTS imh_private_poc
  COMMENT 'Isolated IMH onsite POC; synthetic only, no patient data';
CREATE SCHEMA IF NOT EXISTS imh_private_poc.synthetic_ops;
CREATE SCHEMA IF NOT EXISTS imh_private_poc.restricted_ops;

CREATE TABLE IF NOT EXISTS imh_private_poc.synthetic_ops.hospital_daily
  COMMENT 'Twelve fictional hospital-day aggregates, not clinical decision support'
AS SELECT CAST(day AS DATE) AS service_date, hospital, visits, wait_minutes
FROM VALUES
  ('2026-09-01','North Demo',100,20),('2026-09-02','North Demo',120,22),
  ('2026-09-03','North Demo',130,35),('2026-09-04','North Demo',150,48),
  ('2026-09-01','South Demo',80,18),('2026-09-02','South Demo',90,19),
  ('2026-09-03','South Demo',100,20),('2026-09-04','South Demo',110,21),
  ('2026-09-01','West Demo',60,15),('2026-09-02','West Demo',70,16),
  ('2026-09-03','West Demo',80,17),('2026-09-04','West Demo',90,18)
AS v(day,hospital,visits,wait_minutes);

SELECT assert_true(COUNT(*) = 12 AND SUM(visits) = 1180,
  'Synthetic fixture mismatch; stop rather than overwriting existing data')
FROM imh_private_poc.synthetic_ops.hospital_daily;

CREATE TABLE IF NOT EXISTS imh_private_poc.restricted_ops.hospital_costs
  COMMENT 'Synthetic denial fixture; withhold SELECT from the MCP workload identity'
AS SELECT CAST(day AS DATE) AS service_date, hospital, cost_per_visit_usd, staffing_cost_usd
FROM VALUES
  ('2026-09-01','North Demo',412.50,88000),('2026-09-02','North Demo',430.00,91000),
  ('2026-09-03','North Demo',455.25,94500),('2026-09-04','North Demo',478.75,99000),
  ('2026-09-01','South Demo',390.00,61000),('2026-09-02','South Demo',395.50,62500),
  ('2026-09-03','South Demo',401.00,64000),('2026-09-04','South Demo',408.25,65500),
  ('2026-09-01','West Demo',360.75,44000),('2026-09-02','West Demo',366.00,45000),
  ('2026-09-03','West Demo',371.50,46000),('2026-09-04','West Demo',377.00,47500)
AS v(day,hospital,cost_per_visit_usd,staffing_cost_usd);

CREATE FUNCTION IF NOT EXISTS imh_private_poc.synthetic_ops.hospitals_over_wait_threshold(
  threshold_minutes DOUBLE
)
RETURNS TABLE (hospital STRING, service_date DATE, wait_minutes INT)
COMMENT 'Synthetic hospital-days at or above threshold; not hospital-level averages'
RETURN SELECT hospital, service_date, wait_minutes
FROM imh_private_poc.synthetic_ops.hospital_daily
WHERE wait_minutes >= threshold_minutes;

SELECT hospital, service_date, wait_minutes
FROM imh_private_poc.synthetic_ops.hospitals_over_wait_threshold(25)
ORDER BY wait_minutes DESC, service_date DESC, hospital;
