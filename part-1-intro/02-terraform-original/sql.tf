resource "azurerm_mssql_server" "sql" {
  name                = "sql-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  version             = "12.0"

  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  azuread_administrator {
    login_username              = azurerm_user_assigned_identity.mi.name
    object_id                   = azurerm_user_assigned_identity.mi.principal_id
    tenant_id                   = azurerm_user_assigned_identity.mi.tenant_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "appdb" {
  name        = "appdb"
  server_id   = azurerm_mssql_server.sql.id
  sku_name    = var.db_sku_name
  max_size_gb = local.db_sku_tier == "Basic" ? 2 : 250
}
