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
  vnet3_cidr    = "10.30.0.0/16"
  vnet3_gw_cidr = "10.30.255.0/27"
  vnet4_cidr    = "10.40.0.0/16"
  vnet4_vm_cidr = "10.40.1.0/24"
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
# VNet4 (on-prem sim) + strongSwan VM
#####################
resource "azurerm_virtual_network" "vnet4" {
  name                = "vnet4"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
  address_space       = [local.vnet4_cidr]
}

resource "azurerm_subnet" "vnet4_vm" {
  name                 = "snet-onprem"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.vnet4.name
  address_prefixes     = [local.vnet4_vm_cidr]
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

  # ICMP in VNet (สำหรับ ping ทดสอบ)
  security_rule {
    name                       = "allow-icmp-vnet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
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
  name                = "nic-onprem"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = azurerm_subnet.vnet4_vm.id
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
            leftsubnet=0.0.0.0/0
            leftupdown=/etc/ipsec.d/vti.sh

            right=${azurerm_public_ip.gw3_pip.ip_address}
            rightid=${azurerm_public_ip.gw3_pip.ip_address}
            rightsubnet=0.0.0.0/0

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
              # route to Azure VNet
              ip route add ${local.vnet3_cidr} dev vti0 2>/dev/null || true
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

  # ถ้าอยาก “ไม่ล็อกนโยบาย” ให้ปล่อย negotiation อัตโนมัติได้เลย โดย ลบ บล็อก ipsec_policy ออกทั้งก้อน — มักช่วยลดปัญหา mismatch ระหว่าง Azure ↔ strongSwan เวลา test/POC
  ipsec_policy {
    # IKE (phase 1)
  ike_encryption   = "AES256"
  ike_integrity    = "SHA256"
  dh_group         = "ECP256"

  # ESP (phase 2) — GCM
  ipsec_encryption = "GCMAES256"
  ipsec_integrity  = "GCMAES256"
  pfs_group        = "ECP256"

    sa_lifetime = 28800 # seconds
    # sa_datasize = 102400000  # (optional) KB; ถ้า validate มี constraint ให้เอาออกหรือใส่ 0 ตามเวอร์ชันโปรไวเดอร์
  }
}

#####################
# Outputs
#####################
output "vm4_public_ip" { value = azurerm_public_ip.vm4_pip.ip_address }
output "vm4_private_ip" { value = azurerm_network_interface.vm4_nic.private_ip_address }
output "gw3_public_ip" { value = azurerm_public_ip.gw3_pip.ip_address }
output "ssh_private_key" {
  value     = tls_private_key.vm4.private_key_pem
  sensitive = true
}
