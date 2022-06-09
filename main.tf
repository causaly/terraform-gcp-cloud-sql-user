resource "random_password" "password" {
  for_each         = { for k, v in var.users : k => v if lookup(v, "password", "") == "" }
  length           = 16
  special          = lookup(each.value, "special", false)
  override_special = lookup(each.value, "override_special", null)
}

resource "google_sql_user" "user" {
  for_each = var.users
  name     = each.key
  instance = var.postgres_instance_name
  password = lookup(each.value, "password", try(random_password.password[each.key].result, ""))
}

resource "postgresql_grant" "permissions" {
  for_each = var.users

  database    = var.database
  role        = lookup(each.value, "role", each.key)
  schema      = "public"
  objects     = lookup(each.value, "objects", [])
  object_type = "table"
  privileges  = lookup(each.value, "permissions", ["SELECT"])
  depends_on  = [google_sql_user.user]
}

resource "postgresql_grant" "seq_permissions" {
  for_each    = { for k, v in var.users : k => v if lookup(v, "seq_permissions", []) != [] }
  database    = var.database
  role        = lookup(each.value, "role", each.key)
  schema      = "public"
  objects     = lookup(each.value, "seq_objects", [])
  object_type = "sequence"
  privileges  = lookup(each.value, "seq_permissions", ["SELECT"])
}

resource "vault_generic_secret" "sqlproxy_secret" {
  for_each = var.users
  path     = "${var.vault_secret_path}/${each.key}"
  data_json = jsonencode(
    {
      "database_user"     = each.key
      "database_password" = lookup(each.value, "password", try(random_password.password[each.key].result, ""))
      "credentials.json"  = lookup({ for k, v in var.users : k => google_service_account_key.sa_key[k].private_key if lookup(v, "create_sa", false) }, each.key, "")
    }
  )
}
