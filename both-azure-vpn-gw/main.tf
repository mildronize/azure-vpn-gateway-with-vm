############################################################
# main.tf — 2 VNets, 2 Ubuntu VMs, 2 VPN Gateways (VNet2VNet)
# Terraform: >= 1.6.0
# Provider : azurerm >= 4.0.0
############################################################

terraform {
  required_version = ">= 1.13.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.52.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

#####################
# Config
#####################
locals {
  location       = "southeastasia"
  admin_username = "azureuser"
  ssh_key_bits   = 4096

  # Addressing
  vnet1_cidr      = "10.10.0.0/16"
  vnet1_subnet_vm = "10.10.1.0/24"
  vnet1_subnet_gw = "10.10.255.0/27" # must be named GatewaySubnet

  vnet2_cidr      = "10.20.0.0/16"
  vnet2_subnet_vm = "10.20.1.0/24"
  vnet2_subnet_gw = "10.20.255.0/27"

  # Shared key for VNet2VNet connection
  ipsec_psk = "Demo-ChangeMe-123!"
}

#####################
# SSH key (for both VMs)
#####################
resource "tls_private_key" "vm" {
  algorithm = "RSA"
  rsa_bits  = local.ssh_key_bits
}

#####################
# Resource groups
#####################
resource "azurerm_resource_group" "rg1" {
  name     = "rg-vnet1"
  location = local.location
}

resource "azurerm_resource_group" "rg2" {
  name     = "rg-vnet2"
  location = local.location
}

#####################
# VNet 1 + Subnets
#####################
resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  address_space       = [local.vnet1_cidr]
}

resource "azurerm_subnet" "vnet1_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = [local.vnet1_subnet_vm]
}

resource "azurerm_subnet" "vnet1_gw" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = [local.vnet1_subnet_gw]
}

#####################
# VNet 2 + Subnets
#####################
resource "azurerm_virtual_network" "vnet2" {
  name                = "vnet2"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name
  address_space       = [local.vnet2_cidr]
}

resource "azurerm_subnet" "vnet2_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg2.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = [local.vnet2_subnet_vm]
}

resource "azurerm_subnet" "vnet2_gw" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg2.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = [local.vnet2_subnet_gw]
}

#####################
# NSGs (allow SSH + ICMP inside VNet)
#####################
resource "azurerm_network_security_group" "nsg1" {
  name                = "nsg-vnet1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-icmp-from-vnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nsg2" {
  name                = "nsg-vnet2"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-icmp-from-vnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

#####################
# NICs + Public IPs + VMs (Ubuntu 22.04)
#####################
# VNet1
resource "azurerm_public_ip" "vm1_pip" {
  name                = "pip-vm1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm1_nic" {
  name                = "nic-vm1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.vnet1_vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm1_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm1_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.vm1_nic.id
  network_security_group_id = azurerm_network_security_group.nsg1.id
}

resource "azurerm_linux_virtual_machine" "vm1" {
  name                            = "vm1"
  location                        = azurerm_resource_group.rg1.location
  resource_group_name             = azurerm_resource_group.rg1.name
  size                            = "Standard_B1s"
  admin_username                  = local.admin_username
  network_interface_ids           = [azurerm_network_interface.vm1_nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = tls_private_key.vm.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-vm1"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# VNet2
resource "azurerm_public_ip" "vm2_pip" {
  name                = "pip-vm2"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm2_nic" {
  name                = "nic-vm2"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.vnet2_vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm2_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm2_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.vm2_nic.id
  network_security_group_id = azurerm_network_security_group.nsg2.id
}

resource "azurerm_linux_virtual_machine" "vm2" {
  name                            = "vm2"
  location                        = azurerm_resource_group.rg2.location
  resource_group_name             = azurerm_resource_group.rg2.name
  size                            = "Standard_B1s"
  admin_username                  = local.admin_username
  network_interface_ids           = [azurerm_network_interface.vm2_nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = tls_private_key.vm.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-vm2"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

#####################
# VPN Gateways (VNet1 & VNet2) — azurerm v4
#####################
# Public IPs for Gateways — MUST be Standard + Static in v4
resource "azurerm_public_ip" "gw1_pip" {
  name                = "pip-gw1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_public_ip" "gw2_pip" {
  name                = "pip-gw2"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_virtual_network_gateway" "gw1" {
  name                = "vngw1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  type       = "Vpn"
  vpn_type   = "RouteBased"
  sku        = "VpnGw1AZ"
  generation = "Generation1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.gw1_pip.id
    subnet_id                     = azurerm_subnet.vnet1_gw.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_network_gateway" "gw2" {
  name                = "vngw2"
  location            = azurerm_resource_group.rg2.location
  resource_group_name = azurerm_resource_group.rg2.name

  type       = "Vpn"
  vpn_type   = "RouteBased"
  sku        = "VpnGw1AZ"
  generation = "Generation1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.gw2_pip.id
    subnet_id                     = azurerm_subnet.vnet2_gw.id
    private_ip_address_allocation = "Dynamic"
  }
}

#####################
# VNet-to-VNet Connections (bidirectional)
#####################
resource "azurerm_virtual_network_gateway_connection" "gw1_to_gw2" {
  name                            = "gw1-to-gw2"
  location                        = azurerm_resource_group.rg1.location
  resource_group_name             = azurerm_resource_group.rg1.name
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.gw1.id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.gw2.id
  shared_key                      = local.ipsec_psk
  enable_bgp                      = false
}

resource "azurerm_virtual_network_gateway_connection" "gw2_to_gw1" {
  name                            = "gw2-to-gw1"
  location                        = azurerm_resource_group.rg2.location
  resource_group_name             = azurerm_resource_group.rg2.name
  type                            = "Vnet2Vnet"
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.gw2.id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.gw1.id
  shared_key                      = local.ipsec_psk
  enable_bgp                      = false
}

#####################
# Outputs
#####################
output "vm1_public_ip" {
  value = azurerm_public_ip.vm1_pip.ip_address
}

output "vm2_public_ip" {
  value = azurerm_public_ip.vm2_pip.ip_address
}

output "vm1_private_ip" {
  value = azurerm_network_interface.vm1_nic.private_ip_address
}

output "vm2_private_ip" {
  value = azurerm_network_interface.vm2_nic.private_ip_address
}

output "ssh_private_key_pem" {
  value     = tls_private_key.vm.private_key_pem
  sensitive = true
}
