resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.suffix}"
  location = var.location

  tags = { drift_test = "v1" }
}

resource "azurerm_user_assigned_identity" "mi" {
  name                = "id-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_role_assignment" "mi_reader_on_rg" {
  scope              = azurerm_resource_group.rg.id
  principal_id       = azurerm_user_assigned_identity.mi.principal_id
  principal_type     = "ServicePrincipal"
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.built_in_role_ids.Reader}"
  description        = "Demo: MI gets Reader on the resource group"
}
