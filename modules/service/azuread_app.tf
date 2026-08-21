locals {
  # Graph API permissions - Delegated
  default_delegated_permissions = "User.Read|User.ReadBasic.All|User.Read.All|GroupMember.Read.All|Application.Read.All|Organization.Read.All"

  app_role_id_map = {
    "Reviewer"     = "0a1b7425-f55a-44a6-9caa-b9a5cc9448da"
    "HelpDesk"     = "a94e83da-b314-4232-b8c8-94508c5ed533"
    "EndUser"      = "e856de81-1e53-486a-8668-7d564866ae39"
    "DesktopAdmin" = "ed0cdef0-4267-4470-bfff-5e0b6944f9e4"
    "WvdAdmin"     = "d1c2ade8-98f8-45fd-aa4a-6d06b947c66f"
    "RestClient"   = "3807160f-e77a-4fcf-959a-df572bcc3767"
  }

  flat_role_assignments = flatten([
    for role_name, users in var.app_role_assignments : [
      for user in users : {
        key       = "${role_name}-${user}"
        role_name = role_name
        role_id   = local.app_role_id_map[role_name]
        user      = user
      }
    ]
  ])

  role_assignments_map = { for ra in local.flat_role_assignments : ra.key => ra }

  # Unique user identifiers to look up (avoids duplicate data source reads)
  unique_role_assignee_users = toset(flatten(values(var.app_role_assignments)))
}

# --------------------------------------------------------------------------- #
# Azure AD Application
# --------------------------------------------------------------------------- #
resource "azuread_application" "nme_app" {
  display_name     = var.azuread_app_name
  sign_in_audience = "AzureADMultipleOrgs"

  web {
    homepage_url  = local.web_app_url
    logout_url    = local.logout_url
    redirect_uris = [local.web_app_url, local.login_url]

    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }

  # ---- App Roles --------------------------------------------------------- #
  app_role {
    allowed_member_types = ["User"]
    display_name         = "Reviewer"
    description          = "View access to all areas of NME; no ability to save or make changes."
    id                   = "0a1b7425-f55a-44a6-9caa-b9a5cc9448da"
    value                = "Reviewer"
    enabled              = true
  }

  app_role {
    allowed_member_types = ["User"]
    display_name         = "Help Desk"
    description          = "Complete access to User sessions only."
    id                   = "a94e83da-b314-4232-b8c8-94508c5ed533"
    value                = "HelpDesk"
    enabled              = true
  }

  app_role {
    allowed_member_types = ["User"]
    display_name         = "End-user"
    description          = "View & manage own sessions (Message, Log off, Disconnect). Personal desktop users can restart, power off and power their personal desktops."
    id                   = "e856de81-1e53-486a-8668-7d564866ae39"
    value                = "EndUser"
    enabled              = true
  }

  app_role {
    allowed_member_types = ["User"]
    display_name         = "Desktop Admin"
    description          = "Complete access to User sessions, ability to view Host Pools, hosts and restart them, but no ability to add/remove or change any settings."
    id                   = "ed0cdef0-4267-4470-bfff-5e0b6944f9e4"
    value                = "DesktopAdmin"
    enabled              = true
  }

  app_role {
    allowed_member_types = ["User"]
    display_name         = "WVD Admin"
    description          = "Complete access to all areas of NME."
    id                   = "d1c2ade8-98f8-45fd-aa4a-6d06b947c66f"
    value                = "WvdAdmin"
    enabled              = true
  }

  app_role {
    allowed_member_types = ["Application"]
    display_name         = "Rest client"
    description          = "Rest client"
    id                   = "3807160f-e77a-4fcf-959a-df572bcc3767"
    value                = "RestClient"
    enabled              = true
  }

  # ---- API Permissions --------------------------------------------------- #

  # Microsoft Graph
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    # Application permissions
    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["GroupMember.Read.All"]
      type = "Role"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["User.Read.All"]
      type = "Role"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.app_role_ids["Organization.Read.All"]
      type = "Role"
    }

    # Delegated permissions
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.ReadBasic.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["User.Read.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["GroupMember.Read.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["Application.Read.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["Organization.Read.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["AppRoleAssignment.ReadWrite.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["Application.ReadWrite.All"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["Mail.Send"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["offline_access"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["openid"]
      type = "Scope"
    }
    resource_access {
      id   = azuread_service_principal.msgraph.oauth2_permission_scope_ids["profile"]
      type = "Scope"
    }
  }

  # Azure Resource Manager / Service Management API (environment-dependent)
  dynamic "required_resource_access" {
    for_each = local.has_arm_api ? [1] : []
    content {
      resource_app_id = local.arm_api_app_id[var.azure_environment]

      resource_access {
        id   = azuread_service_principal.arm_api[0].oauth2_permission_scope_ids["user_impersonation"]
        type = "Scope"
      }
    }
  }
}

# Look up the ARM / Service Management API SP to resolve permission IDs
resource "azuread_service_principal" "arm_api" {
  count        = local.has_arm_api ? 1 : 0
  client_id    = local.arm_api_app_id[var.azure_environment]
  use_existing = true
}

# --------------------------------------------------------------------------- #
# Service Principal
# --------------------------------------------------------------------------- #
resource "azuread_service_principal" "nme_app" {
  client_id                    = azuread_application.nme_app.client_id
  app_role_assignment_required = true
  tags                         = ["WindowsAzureActiveDirectoryIntegratedApp"]
}

# --------------------------------------------------------------------------- #
# Key Vault Certificate for Scripted Actions
# --------------------------------------------------------------------------- #
resource "azurerm_key_vault_certificate" "scripted_action_cert" {
  name         = "nmw-scripted-action-cert"
  key_vault_id = azurerm_key_vault.key_vault.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=nmw-scripted-action-cert"
      validity_in_months = 120

      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }
  }

  depends_on = [
    azurerm_key_vault.key_vault,
    azurerm_role_assignment.key_vault_deployer_certificates_officer,
    null_resource.wait_for_key_vault_private_dns,
  ]
}

# --------------------------------------------------------------------------- #
# Self-signed certificate for Azure AD app authentication
# Used by the webapp for features that do not support Managed Identity auth.
# --------------------------------------------------------------------------- #
resource "azurerm_key_vault_certificate" "app_auth_cert" {
  name         = var.app_cert_name
  key_vault_id = azurerm_key_vault.key_vault.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=${var.app_cert_name}"
      validity_in_months = var.app_cert_lifetime_months

      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }
  }

  depends_on = [
    azurerm_key_vault.key_vault,
    azurerm_role_assignment.key_vault_deployer_certificates_officer,
    null_resource.wait_for_key_vault_private_dns,
  ]
}



# --------------------------------------------------------------------------- #
# Application Certificate Credential (attach KV cert to AD app)
# --------------------------------------------------------------------------- #
resource "azuread_application_certificate" "scripted_action" {
  application_id = azuread_application.nme_app.id
  type           = "AsymmetricX509Cert"
  value          = azurerm_key_vault_certificate.scripted_action_cert.certificate_data_base64
  end_date       = azurerm_key_vault_certificate.scripted_action_cert.certificate_attribute[0].expires
}

# --------------------------------------------------------------------------- #
# Application Certificate Credential – App Auth (for non-MI features)
# --------------------------------------------------------------------------- #
resource "azuread_application_certificate" "app_auth" {
  application_id = azuread_application.nme_app.id
  type           = "AsymmetricX509Cert"
  value          = azurerm_key_vault_certificate.app_auth_cert.certificate_data_base64
  end_date       = azurerm_key_vault_certificate.app_auth_cert.certificate_attribute[0].expires
}

# --------------------------------------------------------------------------- #
# Key Vault RBAC Role Assignments – NME App Service Principal
# --------------------------------------------------------------------------- #
resource "azurerm_role_assignment" "nme_app_sp_secrets_user" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.nme_app.object_id
}

resource "azurerm_role_assignment" "nme_app_sp_certificates_officer" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = azuread_service_principal.nme_app.object_id
}

# --------------------------------------------------------------------------- #
# Role Assignments
# --------------------------------------------------------------------------- #
resource "azurerm_role_assignment" "nme_sp_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.nme_app.object_id
}

resource "azurerm_role_assignment" "nme_sp_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.nme_app.object_id
}

resource "azurerm_role_assignment" "nme_sp_backup_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Backup Reader"
  principal_id         = azuread_service_principal.nme_app.object_id
}

data "azuread_user" "role_assignees" {
  for_each            = local.unique_role_assignee_users
  user_principal_name = each.value
}

resource "azuread_app_role_assignment" "user_roles" {
  for_each = local.role_assignments_map

  app_role_id         = each.value.role_id
  principal_object_id = data.azuread_user.role_assignees[each.value.user].object_id
  resource_object_id  = azuread_service_principal.nme_app.object_id
}
