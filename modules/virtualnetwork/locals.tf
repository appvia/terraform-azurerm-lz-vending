locals {
  # subscription_resource_id is the ARM resource ID of the supplied subscription id.
  subscription_resource_id = "/subscriptions/${var.subscription_id}"
}

locals {
  # virtual_networks_resource_ids is a map of the virtual network resource IDs.
  # we construct these to better enable testing of values in the plan
  virtual_network_resource_ids = {
    for k, v in var.virtual_networks : k => "${local.subscription_resource_id}/resourceGroups/${v.resource_group_name}/providers/Microsoft.Network/virtualNetworks/${v.name}"
  }

  # virtual_networks_hub_peering_map is a map of the virtual network hub peerings

  # hub_peering_map is a map of the virtual network hub peerings for those networks
  # with hub peering enabled
  hub_peering_map = {
    for k, v in var.virtual_networks : k => {
      # Peering this network to the remote network
      outbound = {
        name               = coalesce(v.hub_peering_name_tohub, "peer-${uuidv5("url", v.hub_network_resource_id)}")
        this_resource_id   = azapi_resource.vnet[k].id
        remote_resource_id = v.hub_network_resource_id
      },
      # Peering the remote network to this network
      inbound = {
        name               = coalesce(v.hub_peering_name_fromhub, "peer-${uuidv5("url", local.virtual_network_resource_ids[k])}")
        this_resource_id   = v.hub_network_resource_id
        remote_resource_id = azapi_resource.vnet[k].id
      }
    } if v.hub_peering_enabled
  }

  # vwan_propagated_routetables_resource_ids is a map of the virtual network vwan propagated routetable ids
  # for each virtual network that enabled for vwan connectivity.
  vwan_propagated_routetables_resource_ids = {
    for k, v in var.virtual_networks : k => coalescelist(
      [
        for i in v.vwan_propagated_routetables_resource_ids : { id = i }
      ],
      [
        { id = "${v.vwan_hub_resource_id}/hubRouteTables/defaultRouteTable" }
      ]
    ) if v.vwan_connection_enabled
  }

  # vwan_propagated_routetables_labels is a map of the virtual network vwan propagated routetables labels
  # for each virtual network that enabled for vwan connectivity.
  vwan_propagated_routetables_labels = {
    for k, v in var.virtual_networks : k => coalescelist(
      v.vwan_propagated_routetables_labels,
      ["default"]
    ) if v.vwan_connection_enabled
  }

  # virtual_networks_mesh_peering_map is the data required to create the mesh peerings.
  # That is those peerings between the virtual networks that are supplied in the var.virtual_networks variable
  virtual_networks_mesh_peering_list = flatten([
    for k_src, v_src in local.virtual_network_resource_ids : [
      for k_dst, v_dst in local.virtual_network_resource_ids : {
        source_key              = k_src
        destination_key         = k_dst
        name                    = "peer-${uuidv5("url", v_dst)}"
        this_resource_id        = azapi_resource.vnet[k_src].id
        remote_resource_id      = v_dst
        allow_forwarded_traffic = var.virtual_networks[k_src].mesh_peering_allow_forwarded_traffic
      } if var.virtual_networks[k_dst].mesh_peering_enabled && k_src != k_dst
    ] if var.virtual_networks[k_src].mesh_peering_enabled
  ])
}

locals {
  # resource_group_data is the unique set of resource groups to create to support the virtual network resources
  resource_group_data = toset([
    for k, v in var.virtual_networks : {
      name      = v.resource_group_name
      location  = coalesce(v.location, var.location)
      lock      = v.resource_group_lock_enabled
      lock_name = v.resource_group_lock_name
      tags      = v.resource_group_tags
    } if v.resource_group_creation_enabled
  ])
}
