############################################################
# Hybrid S2S: Azure VPN Gateway (rg-vnet3) <-> strongSwan VM (rg-vnet4)
# Terraform >= 1.6, azurerm >= 4.52
############################################################

terraform {
  required_version = ">= 1.13.5"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.52.0" }
    tls     = { source = "hashicorp/tls", version = ">= 4.0.5" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

#####################
# Config
#####################
locals {
  location       = "southeastasia"
  admin_username = "azureuser"
  ipsec_psk      = "Demo-ChangeMe-123!"
  # Address spaces
  vnet3_cidr        = "10.30.0.0/16"
  vnet3_vm_cidr     = "10.30.1.0/24"
  vnet3_gw_cidr     = "10.30.255.0/27"
  vnet4_cidr        = "10.40.0.0/16"
  vnet4_client_cidr = "10.40.10.0/24"
  vnet4_vpngw_cidr  = "10.40.2.0/24"
}

#####################
# Resource Groups
#####################
resource "azurerm_resource_group" "rg3" {
  name     = "rg-vnet3"
  location = local.location
}

resource "azurerm_resource_group" "rg4" {
  name     = "rg-vnet4"
  location = local.location
}

#####################
# VNet3 (Azure Gateway side)
#####################
resource "azurerm_virtual_network" "vnet3" {
  name                = "vnet3"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name
  address_space       = [local.vnet3_cidr]
}

resource "azurerm_subnet" "vnet3_gw" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg3.name
  virtual_network_name = azurerm_virtual_network.vnet3.name
  address_prefixes     = [local.vnet3_gw_cidr]
}

resource "azurerm_subnet" "vnet3_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg3.name
  virtual_network_name = azurerm_virtual_network.vnet3.name
  address_prefixes     = [local.vnet3_vm_cidr]
}

#####################
# VNet3 NSG and VM
#####################
resource "azurerm_network_security_group" "nsg3" {
  name                = "nsg-azure-vm"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name

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

  # ICMP from on-prem VNet for VPN connectivity testing
  security_rule {
    name                       = "allow-icmp-from-onprem"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.vnet4_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "vm3_pip" {
  name                = "pip-azure-vm"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle { create_before_destroy = true }
}

resource "azurerm_network_interface" "vm3_nic" {
  name                = "nic-azure-vm"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.vnet3_vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm3_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm3_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.vm3_nic.id
  network_security_group_id = azurerm_network_security_group.nsg3.id
}

resource "azurerm_linux_virtual_machine" "vm3" {
  name                            = "vm-azure"
  location                        = azurerm_resource_group.rg3.location
  resource_group_name             = azurerm_resource_group.rg3.name
  size                            = "Standard_B1s"
  admin_username                  = local.admin_username
  network_interface_ids           = [azurerm_network_interface.vm3_nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = tls_private_key.vm4.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-azure-vm"
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

# Gateway Public IP (AZ SKU requires zones)
resource "azurerm_public_ip" "gw3_pip" {
  name                = "pip-gw3"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  lifecycle { create_before_destroy = true }
}

resource "azurerm_virtual_network_gateway" "gw3" {
  name                = "vngw3"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name

  type       = "Vpn"
  vpn_type   = "RouteBased"
  sku        = "VpnGw1AZ"
  generation = "Generation1"

  ip_configuration {
    name                          = "gw3-ipcfg"
    public_ip_address_id          = azurerm_public_ip.gw3_pip.id
    subnet_id                     = azurerm_subnet.vnet3_gw.id
    private_ip_address_allocation = "Dynamic"
  }
}

#####################
# VNet4 (on-prem sim) + strongSwan VM + Client VM
#####################
resource "azurerm_virtual_network" "vnet4" {
  name                = "vnet4"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
  address_space       = [local.vnet4_cidr]
}

# Subnet for VPN Gateway VM (strongSwan)
resource "azurerm_subnet" "vnet4_vpngw" {
  name                 = "snet-vpngw"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.vnet4.name
  address_prefixes     = [local.vnet4_vpngw_cidr]
}

# Subnet for on-prem client VM
resource "azurerm_subnet" "vnet4_client" {
  name                 = "snet-client"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.vnet4.name
  address_prefixes     = [local.vnet4_client_cidr]
}

resource "azurerm_network_security_group" "nsg4" {
  name                = "nsg-onprem"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name

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

  # IPsec (NAT-T)
  security_rule {
    name                       = "allow-ipsec"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = ["500", "4500"]
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # ICMP from Azure VNet for VPN connectivity testing
  security_rule {
    name                       = "allow-icmp-from-azure"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.vnet3_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "vm4_pip" {
  name                = "pip-onprem"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle { create_before_destroy = true }
}

resource "azurerm_network_interface" "vm4_nic" {
  name                  = "nic-vpngw"
  location              = azurerm_resource_group.rg4.location
  resource_group_name   = azurerm_resource_group.rg4.name
  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.vnet4_vpngw.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm4_pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "vm4_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.vm4_nic.id
  network_security_group_id = azurerm_network_security_group.nsg4.id
}

resource "tls_private_key" "vm4" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "vm4" {
  name                            = "vm-onprem-strongswan"
  location                        = azurerm_resource_group.rg4.location
  resource_group_name             = azurerm_resource_group.rg4.name
  size                            = "Standard_B1s"
  admin_username                  = local.admin_username
  network_interface_ids           = [azurerm_network_interface.vm4_nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = tls_private_key.vm4.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-onprem"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # cloud-init: install & configure strongSwan (route-based via VTI)
  custom_data = base64encode(local.vm4_cloud_init)
}

# -------- cloud-init content for strongSwan VM --------
locals {
  vm4_cloud_init = <<-CLOUDCFG
    #cloud-config
    package_update: true
    packages:
      - strongswan
      - traceroute
      - tcpdump
      - ufw

    write_files:
      - path: /etc/strongswan.d/charon.conf
        permissions: "0644"
        content: |
          charon {
            install_routes = 0
            plugins {
              connmark { load = no }
            }
          }

      - path: /etc/ipsec.secrets
        permissions: "0600"
        content: |
          ${azurerm_public_ip.gw3_pip.ip_address} ${azurerm_public_ip.vm4_pip.ip_address} : PSK "${local.ipsec_psk}"

      - path: /etc/ipsec.conf
        permissions: "0644"
        content: |
          config setup
            uniqueids=no

          conn azure-s2s-vti
            keyexchange=ikev2
            ike=aes256gcm16-prfsha256-ecp256!
            esp=aes256gcm16-ecp256!
            dpdaction=restart
            dpddelay=30s
            rekey=yes
            ikelifetime=24h
            lifetime=8h
            rekeymargin=3m
            authby=psk
            type=tunnel

            left=%defaultroute
            leftid=${azurerm_public_ip.vm4_pip.ip_address}
            leftsubnet=${local.vnet4_cidr}
            leftupdown=/etc/ipsec.d/vti.sh

            right=${azurerm_public_ip.gw3_pip.ip_address}
            rightid=${azurerm_public_ip.gw3_pip.ip_address}
            rightsubnet=${local.vnet3_cidr}

            mark=42
            auto=start

      - path: /etc/ipsec.d/vti.sh
        permissions: "0755"
        content: |
          #!/usr/bin/env bash
          set -e
          case "$PLUTO_VERB" in
            up-client)
              ip tunnel add vti0 local "$PLUTO_ME" remote "$PLUTO_PEER" mode vti key 42 || true
              ip link set vti0 up
              sysctl -w net.ipv4.conf.vti0.disable_policy=1 >/dev/null
              ip addr add 10.240.0.2/30 dev vti0 2>/dev/null || true
              # Route to Azure VNet via VTI tunnel
              ip route add ${local.vnet3_cidr} dev vti0 2>/dev/null || true
              # Allow return traffic from Azure to client subnet
              ip route add ${local.vnet4_client_cidr} via $(ip route | grep ${local.vnet4_vpngw_cidr} | awk '{print $9}' | head -1) 2>/dev/null || true
              ;;
            down-client)
              ip link del vti0 2>/dev/null || true
              ;;
          esac
          exit 0

      - path: /etc/sysctl.d/99-ipsec.conf
        permissions: "0644"
        content: |
          net.ipv4.ip_forward=1
          net.ipv4.conf.all.rp_filter=2
          net.ipv4.conf.default.rp_filter=2

    runcmd:
      - sysctl --system
      - ufw allow 22/tcp
      - ufw allow 500/udp
      - ufw allow 4500/udp
      - ufw --force enable
      - systemctl restart strongswan
      - systemctl enable strongswan
  CLOUDCFG
}

#####################
# VNet4 Client VM (simulated on-prem workstation)
#####################
resource "azurerm_network_security_group" "nsg4_client" {
  name                = "nsg-onprem-client"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name

  security_rule {
    name                       = "allow-ssh-from-vpngw"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.vnet4_vpngw_cidr
    destination_address_prefix = "*"
  }

  # ICMP from Azure VNet for VPN connectivity testing
  security_rule {
    name                       = "allow-icmp-from-azure"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.vnet3_cidr
    destination_address_prefix = "*"
  }

  # ICMP from local VNet (strongSwan subnet)
  security_rule {
    name                       = "allow-icmp-from-local"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.vnet4_vpngw_cidr
    destination_address_prefix = "*"
  }
}

# Route table for client VM to route Azure traffic through strongSwan
resource "azurerm_route_table" "vnet4_client_rt" {
  name                = "rt-onprem-client"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name

  route {
    name                   = "to-azure-via-vpngw"
    address_prefix         = local.vnet3_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.vm4_nic.private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "vnet4_client_rt_assoc" {
  subnet_id      = azurerm_subnet.vnet4_client.id
  route_table_id = azurerm_route_table.vnet4_client_rt.id
}

resource "azurerm_network_interface" "vm4_client_nic" {
  name                = "nic-onprem-client"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.vnet4_client.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "vm4_client_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.vm4_client_nic.id
  network_security_group_id = azurerm_network_security_group.nsg4_client.id
}

resource "azurerm_linux_virtual_machine" "vm4_client" {
  name                            = "vm-onprem-client"
  location                        = azurerm_resource_group.rg4.location
  resource_group_name             = azurerm_resource_group.rg4.name
  size                            = "Standard_B1s"
  admin_username                  = local.admin_username
  network_interface_ids           = [azurerm_network_interface.vm4_client_nic.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = tls_private_key.vm4.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-onprem-client"
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
# Local Network Gateway (represents on-prem)
#####################
resource "azurerm_local_network_gateway" "lng_onprem" {
  name                = "lng-onprem"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name

  gateway_address = azurerm_public_ip.vm4_pip.ip_address
  address_space   = [local.vnet4_cidr] # prefixes behind on-prem
}

#####################
# Azure <-> On-Prem Connection (S2S)
#####################
resource "azurerm_virtual_network_gateway_connection" "gw3_to_onprem" {
  name                = "gw3-to-onprem"
  location            = azurerm_resource_group.rg3.location
  resource_group_name = azurerm_resource_group.rg3.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.gw3.id
  local_network_gateway_id   = azurerm_local_network_gateway.lng_onprem.id
  shared_key                 = local.ipsec_psk
  enable_bgp                 = false

  # Removed ipsec_policy block to allow automatic negotiation with strongSwan
  # This prevents cipher mismatch issues between Azure and strongSwan
}

#####################
# Outputs
#####################
output "azure_vm_public_ip" {
  description = "Public IP of Azure VM (for SSH management)"
  value       = azurerm_public_ip.vm3_pip.ip_address
}

output "azure_vm_private_ip" {
  description = "Private IP of Azure VM (VPN test target)"
  value       = azurerm_network_interface.vm3_nic.private_ip_address
}

output "vpngw_vm_public_ip" {
  description = "Public IP of VPN Gateway VM (strongSwan)"
  value       = azurerm_public_ip.vm4_pip.ip_address
}

output "vpngw_vm_private_ip" {
  description = "Private IP of VPN Gateway VM (strongSwan)"
  value       = azurerm_network_interface.vm4_nic.private_ip_address
}

output "onprem_client_private_ip" {
  description = "Private IP of on-prem client VM (no public IP)"
  value       = azurerm_network_interface.vm4_client_nic.private_ip_address
}

output "azure_vpn_gateway_public_ip" {
  description = "Public IP of Azure VPN Gateway"
  value       = azurerm_public_ip.gw3_pip.ip_address
}

output "ssh_private_key" {
  description = "SSH private key for all VMs"
  value       = tls_private_key.vm4.private_key_pem
  sensitive   = true
}
