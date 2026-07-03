output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "sql_server_fqdn" {
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
  description = "FQDN of the SQL server. Reachable only inside the VNet (public access disabled)."
}

output "sql_database_name" {
  value = azurerm_mssql_database.appdb.name
}

output "managed_identity_id" {
  value       = azurerm_user_assigned_identity.mi.id
  description = "Resource ID of the user-assigned MI; attach to a workload to gain SQL admin access."
}

output "private_endpoint_ip" {
  value       = try(azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address, null)
  description = "Private IP assigned to the SQL server's private endpoint."
}
