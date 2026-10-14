locals {
  group_names = {
    phi_full      = var.groups.phi_full
    clinician_slc = var.groups.clinician_slc
    analyst       = var.groups.analyst
  }
  schema_full_name = "${var.uc_catalog}.${var.uc_schema}"
}

# ---------- Account level ----------

resource "databricks_group" "this" {
  for_each     = var.create_groups ? local.group_names : {}
  provider     = databricks.account
  display_name = each.value
}

data "databricks_group" "this" {
  for_each     = var.create_groups ? {} : local.group_names
  provider     = databricks.account
  display_name = each.value
}

locals {
  group_ids = { for k, v in local.group_names :
    k => var.create_groups ? databricks_group.this[k].id : data.databricks_group.this[k].id
  }
}

resource "databricks_mws_permission_assignment" "groups" {
  for_each     = local.group_ids
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = each.value
  permissions  = ["USER"]
}

# APIM's managed identity as a Databricks service principal (application_id = UMI client ID).
resource "databricks_service_principal" "umi" {
  provider       = databricks.account
  application_id = var.umi_client_id
  display_name   = var.umi_display_name
}

resource "databricks_group_member" "umi" {
  provider  = databricks.account
  group_id  = local.group_ids[var.agent_group_key]
  member_id = databricks_service_principal.umi.id
}

resource "databricks_mws_permission_assignment" "umi" {
  provider     = databricks.account
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.umi.id
  permissions  = ["USER"]
}

resource "databricks_custom_app_integration" "foundry" {
  count         = var.create_oauth_app ? 1 : 0
  provider      = databricks.account
  name          = "foundry-uc-per-user"
  confidential  = true
  redirect_urls = var.oauth_redirect_urls
  scopes        = ["all-apis", "offline_access"]
}

# ---------- Workspace level ----------

resource "databricks_catalog" "this" {
  count        = var.create_catalog ? 1 : 0
  provider     = databricks.workspace
  name         = var.uc_catalog
  storage_root = var.catalog_storage_root == "" ? null : var.catalog_storage_root
  comment      = "Synthetic data only. UC agent gateway demo."
}

resource "databricks_schema" "this" {
  count        = var.create_catalog ? 1 : 0
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this[0].name
  name         = var.uc_schema
}

# databricks_grant is non-authoritative: it adds these privileges and leaves other grants alone.
resource "databricks_grant" "catalog" {
  for_each   = local.group_names
  provider   = databricks.workspace
  catalog    = var.uc_catalog
  principal  = each.value
  privileges = ["USE_CATALOG"]
  depends_on = [databricks_catalog.this, databricks_mws_permission_assignment.groups]
}

resource "databricks_grant" "schema" {
  for_each   = local.group_names
  provider   = databricks.workspace
  schema     = local.schema_full_name
  principal  = each.value
  privileges = ["USE_SCHEMA", "SELECT", "EXECUTE"]
  depends_on = [databricks_schema.this, databricks_mws_permission_assignment.groups]
}

resource "databricks_permissions" "warehouse" {
  count           = var.manage_warehouse_permissions ? 1 : 0
  provider        = databricks.workspace
  sql_endpoint_id = var.warehouse_id

  dynamic "access_control" {
    for_each = local.group_names
    content {
      group_name       = access_control.value
      permission_level = "CAN_USE"
    }
  }
}

# Table, synthetic rows, row filter, masks and the get_patients function. Run once: databricks jobs run-now <job_id>.
resource "databricks_workspace_file" "uc_objects" {
  count    = var.deploy_uc_objects ? 1 : 0
  provider = databricks.workspace
  path     = var.workspace_sql_path
  content_base64 = base64encode(templatefile("${path.module}/uc_objects.sql.tftpl", {
    catalog       = var.uc_catalog
    schema        = var.uc_schema
    phi_full      = var.groups.phi_full
    clinician_slc = var.groups.clinician_slc
    analyst       = var.groups.analyst
  }))
}

resource "databricks_job" "uc_objects" {
  count    = var.deploy_uc_objects ? 1 : 0
  provider = databricks.workspace
  name     = "uc-agent-gateway-setup-${var.uc_catalog}-${var.uc_schema}"

  task {
    task_key = "uc_objects"
    sql_task {
      warehouse_id = var.warehouse_id
      file {
        path   = databricks_workspace_file.uc_objects[0].path
        source = "WORKSPACE"
      }
    }
  }

  depends_on = [databricks_schema.this]
}
