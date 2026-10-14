# New-workspace synthetic fixtures

[synthetic-fixtures.sql](synthetic-fixtures.sql) is implemented but **not run**.
Run it only in the approved new Premium workspace with an assigned metastore
and selected SQL warehouse. Do not run against the existing public demo or
customer EDP. The catalog is fixed as `imh_private_poc`, matching the adapter's
`SYNTHETIC_CATALOG` configuration.

The operations table has 12 rows / 1180 visits. Threshold 25 returns two rows:
North Demo, 2026-09-04, 48; North Demo, 2026-09-03, 35.
The restricted table is a denial fixture; successful access is a failed denial
test, not something to reinterpret as success.

After workspace identity registration, use Catalog Explorer permissions as the
fixture owner to grant:

- USE CATALOG on `imh_private_poc`.
- USE SCHEMA on the two fixture schemas.
- SELECT on `synthetic_ops.hospital_daily`.
- EXECUTE on `synthetic_ops.hospitals_over_wait_threshold`.
- Warehouse CAN USE.

**Do not grant** SELECT on `restricted_ops.hospital_costs`, ALL PRIVILEGES,
catalog ownership or inherited broad group membership to the runtime identity.
Inspect effective permissions, not merely the absence of one direct grant.
Verify that the function owner has explicit source-table access; UC function
execution uses owner privileges for its underlying objects.

The script does not overwrite existing tables/functions. Confirm actual
function definition, known-answer rows and effective grants before acceptance.
It does not implement row/column policies or human OBO.
