# Hybrid VPN Configuration - Critical Analysis Report

## Executive Summary

The hybrid directory configuration is **fundamentally incomplete** and does not match the intended hybrid architecture. Based on the reference implementation in `both-azure-vpn-gw`, the hybrid model should demonstrate a full site-to-site VPN scenario with client VMs on both sides, but currently lacks critical infrastructure components.

**Status: NOT READY FOR TESTING** ❌

---

## Architecture Comparison

### Reference Architecture (both-azure-vpn-gw)
```
┌─────────────────────────────────────────┐  ┌─────────────────────────────────────────┐
│ VNet1 (10.10.0.0/16)                    │  │ VNet2 (10.20.0.0/16)                    │
│                                         │  │                                         │
│  ┌─────────────────────────────────┐   │  │   ┌─────────────────────────────────┐  │
│  │ Subnet: snet-vm (10.10.1.0/24)  │   │  │   │ Subnet: snet-vm (10.20.1.0/24)  │  │
│  │  • VM1 (Ubuntu)                 │   │  │   │  • VM2 (Ubuntu)                 │  │
│  │  • Public IP                    │   │  │   │  • Public IP                    │  │
│  │  • NSG (SSH + ICMP)             │   │  │   │  • NSG (SSH + ICMP)             │  │
│  └─────────────────────────────────┘   │  │   └─────────────────────────────────┘  │
│                                         │  │                                         │
│  ┌─────────────────────────────────┐   │  │   ┌─────────────────────────────────┐  │
│  │ GatewaySubnet (10.10.255.0/27)  │   │  │   │ GatewaySubnet (10.20.255.0/27)  │  │
│  │  • Azure VPN Gateway (VpnGw1AZ) │◄──┼──┼──►│  • Azure VPN Gateway (VpnGw1AZ) │  │
│  │  • Public IP (Zone-redundant)   │   │  │   │  • Public IP (Zone-redundant)   │  │
│  └─────────────────────────────────┘   │  │   └─────────────────────────────────┘  │
└─────────────────────────────────────────┘  └─────────────────────────────────────────┘
        VM1 ──► Azure GW1 ◄═══VNet2VNet═══► Azure GW2 ──► VM2
```

### Expected Hybrid Architecture (what it SHOULD be)
```
┌──────────────────────────────────────────┐  ┌─────────────────────────────────────────┐
│ VNet4 (10.40.0.0/16) - "On-Prem" Sim     │  │ VNet3 (10.30.0.0/16) - Azure Cloud      │
│                                          │  │                                         │
│  ┌────────────────────────────────────┐  │  │   ┌─────────────────────────────────┐  │
│  │ Subnet: snet-client (10.40.1.0/24) │  │  │   │ Subnet: snet-vm (10.30.1.0/24)  │  │
│  │  • On-prem Client VM (Ubuntu)      │  │  │   │  • Azure VM (Ubuntu)            │  │
│  │  • NO public IP                    │  │  │   │  • Public IP (for mgmt)         │  │
│  │  • NSG (ICMP, SSH from local)      │  │  │   │  • NSG (ICMP from VPN)          │  │
│  │                                    │  │  │   │                                 │  │
│  │  Routes:                           │  │  │   │  Routes:                        │  │
│  │   10.30.0.0/16 → 10.40.2.x         │  │  │   │   Auto-injected via VPN GW     │  │
│  └────────────────────────────────────┘  │  │   └─────────────────────────────────┘  │
│                   ▲                      │  │                                         │
│                   │                      │  │   ┌─────────────────────────────────┐  │
│  ┌────────────────▼───────────────────┐  │  │   │ GatewaySubnet (10.30.255.0/27)  │  │
│  │ Subnet: snet-vpngw (10.40.2.0/24)  │  │  │   │  • Azure VPN Gateway (VpnGw1AZ) │  │
│  │  • VPN Gateway VM (strongSwan)     │◄─┼──┼──►│  • Public IP (Zone-redundant)   │  │
│  │  • Public IP (for IPsec tunnel)    │  │  │   └─────────────────────────────────┘  │
│  │  • IP forwarding enabled           │  │  │                                         │
│  │  • VTI tunnel interface            │  │  │                                         │
│  └────────────────────────────────────┘  │  │                                         │
└──────────────────────────────────────────┘  └─────────────────────────────────────────┘

On-prem VM ──► strongSwan VM ◄═══Site-to-Site IPsec═══► Azure VPN GW ──► Azure VM
```

### Current Hybrid Architecture (what it ACTUALLY is)
```
┌──────────────────────────────────────────┐  ┌─────────────────────────────────────────┐
│ VNet4 (10.40.0.0/16) - "On-Prem" Sim     │  │ VNet3 (10.30.0.0/16) - Azure Cloud      │
│                                          │  │                                         │
│  ❌ MISSING: Client VM subnet            │  │   ❌ MISSING: VM subnet                 │
│                                          │  │   ❌ MISSING: Test VM                   │
│  ┌────────────────────────────────────┐  │  │                                         │
│  │ Subnet: snet-onprem (10.40.1.0/24) │  │  │   ┌─────────────────────────────────┐  │
│  │  • VPN Gateway VM (strongSwan)     │◄─┼──┼──►│ GatewaySubnet (10.30.255.0/27)  │  │
│  │  • Public IP                       │  │  │   │  • Azure VPN Gateway (VpnGw1AZ) │  │
│  │  • NSG (SSH, IPsec, ICMP)          │  │  │   │  • Public IP (Zone-redundant)   │  │
│  │  • VTI tunnel to Azure             │  │  │   └─────────────────────────────────┘  │
│  └────────────────────────────────────┘  │  │                                         │
│                                          │  │                                         │
│  ⚠️  This VM is BOTH client AND gateway  │  │   ⚠️  No destination VM to ping        │
└──────────────────────────────────────────┘  └─────────────────────────────────────────┘

strongSwan VM (dual role) ◄═══Site-to-Site IPsec═══► Azure VPN GW ──► ❌ Nothing
```

---

## Critical Issues

### 1. Missing Infrastructure - Azure Side (BLOCKER) 🚨

**Problem:** VNet3 has NO VM subnet and NO test VM

**Current state:**
- VNet3 only contains `GatewaySubnet` (10.30.255.0/27)
- Azure VPN Gateway exists but has nothing behind it
- **Impossible to test end-to-end connectivity**

**Impact:**
- Cannot verify if traffic successfully traverses the VPN tunnel
- No way to test private IP connectivity from on-prem to Azure
- Configuration is untestable without additional manual VM creation

**Expected:**
```terraform
# MISSING in hybrid/main.tf
resource "azurerm_subnet" "vnet3_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg3.name
  virtual_network_name = azurerm_virtual_network.vnet3.name
  address_prefixes     = ["10.30.1.0/24"]
}

resource "azurerm_linux_virtual_machine" "vm3" {
  # Azure-side test VM
  # Should be accessible via VPN from on-prem
}
```

**Fix required:** ✅ Add VM subnet and Ubuntu test VM in VNet3

---

### 2. Missing Infrastructure - On-Prem Side (BLOCKER) 🚨

**Problem:** VNet4 has NO client VM behind the VPN gateway

**Current state:**
- The strongSwan VM serves dual purposes:
  - VPN gateway (IPsec termination)
  - "Client" VM (where you would SSH to test)
- This defeats the purpose of a hybrid architecture demonstration

**Impact:**
- Does not simulate realistic on-prem topology where client systems sit behind a firewall/VPN appliance
- Cannot test IP forwarding and routing through the strongSwan gateway
- Misrepresents how hybrid connectivity actually works

**Expected:**
```terraform
# MISSING in hybrid/main.tf
resource "azurerm_subnet" "vnet4_client" {
  name                 = "snet-client"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.vnet4.name
  address_prefixes     = ["10.40.10.0/24"]
}

resource "azurerm_linux_virtual_machine" "vm4_client" {
  # On-prem client VM (no public IP)
  # Default route points to strongSwan VM
  # Tests connectivity by pinging Azure VM private IP
}
```

**Fix required:** ✅ Add client subnet and client VM in VNet4, configure strongSwan for IP forwarding

---

### 3. IPsec Policy Cipher Mismatch (WILL FAIL) 🔴

**Location:** `hybrid/main.tf:341-354` vs `hybrid/main.tf:253`

**Problem:** Azure side and strongSwan side negotiate incompatible ciphers

| Side | IKE Encryption | ESP Encryption | ESP Integrity |
|------|----------------|----------------|---------------|
| **Azure** (line 343-349) | `AES256` (CBC) | `GCMAES256` | `GCMAES256` |
| **strongSwan** (line 253) | `aes256gcm16` | `aes256gcm16` | (implied by GCM) |

**Technical explanation:**
- Azure config: `ike_encryption = "AES256"` means **AES-256-CBC** for IKEv2 phase 1
- strongSwan config: `ike=aes256gcm16-prfsha256-ecp256!` means **AES-256-GCM** for IKE
- The `!` suffix means "only accept this suite, no fallback"
- **IKE phase 1 will fail because CBC ≠ GCM**

**Additional inconsistency:**
- Azure ESP uses GCM (authenticated encryption, no separate integrity check needed)
- strongSwan ESP also uses GCM
- **BUT** the IKE phase must match first, and it doesn't

**Impact:**
- Tunnel will fail to establish during IKEv2 negotiation
- Azure portal will show connection status: "Connecting" or "Not connected"
- strongSwan logs will show: `no matching proposal found`

**Fix options:**

**Option A - Let Azure auto-negotiate (RECOMMENDED):**
```terraform
# Remove the entire ipsec_policy block from lines 341-354
# Azure will negotiate compatible defaults with strongSwan
resource "azurerm_virtual_network_gateway_connection" "gw3_to_onprem" {
  # ... other config ...
  shared_key = local.ipsec_psk
  enable_bgp = false
  # NO ipsec_policy block
}
```

**Option B - Match strongSwan to Azure:**
```bash
# In cloud-init, change strongSwan config to use CBC
ike=aes256-sha256-ecp256!
esp=aes256gcm16-ecp256!
```

---

### 4. Traffic Selector Mismatch (ROUTING FAILURE) 🔴

**Location:** `hybrid/main.tf:266,271` vs `hybrid/main.tf:323`

**Problem:** strongSwan advertises 0.0.0.0/0 but Azure expects specific prefixes

**Current configuration:**

strongSwan side (lines 266-271):
```bash
leftsubnet=0.0.0.0/0    # "I'll send ALL traffic through tunnel"
rightsubnet=0.0.0.0/0   # "I expect ALL traffic from remote"
```

Azure Local Network Gateway (line 323):
```terraform
address_space = [local.vnet4_cidr]  # Only 10.40.0.0/16
```

**Impact:**
- Azure thinks on-prem network is 10.40.0.0/16
- strongSwan tries to negotiate 0.0.0.0/0 ↔ 0.0.0.0/0
- Traffic selectors won't match, tunnel may establish but **won't pass traffic**
- Or tunnel may fail entirely depending on Azure's strictness

**Why this matters:**
Route-based VPN with VTI doesn't actually care about traffic selectors for routing (that's done via the `vti0` interface routes), but the IPsec SA (Security Association) still negotiates them during IKE phase 2. Mismatched selectors = failed SA = no data plane.

**Fix required:**
```bash
# In cloud-init template (line 266-271), change to:
leftsubnet=10.40.0.0/16    # Match local.vnet4_cidr
rightsubnet=10.30.0.0/16   # Match local.vnet3_cidr
```

---

### 5. NSG ICMP Rule Won't Work for VPN Traffic ⚠️

**Location:** `hybrid/main.tf:140-151`

**Problem:** ICMP rule uses `source_address_prefix = "VirtualNetwork"` which doesn't include VPN-routed traffic

**Current configuration:**
```terraform
security_rule {
  name                       = "allow-icmp-vnet"
  source_address_prefix      = "VirtualNetwork"  # ❌ Won't match VPN traffic
  # ...
}
```

**Technical explanation:**
- `VirtualNetwork` service tag includes:
  - VNet's local address space
  - Peered VNets
  - **Does NOT include VPN gateway connections by default**
- Traffic from 10.30.0.0/16 (Azure) arriving via VPN tunnel won't match this rule
- ICMP packets will be dropped by NSG

**Fix required:**
```terraform
security_rule {
  name                       = "allow-icmp-from-azure"
  priority                   = 120
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Icmp"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "10.30.0.0/16"  # ✅ Explicit Azure VNet CIDR
  destination_address_prefix = "*"
}
```

---

### 6. Routing Configuration Issues ⚠️

**Problem:** strongSwan VM will need additional routing configuration once client VM is added

**Current state:**
- strongSwan VM has `net.ipv4.ip_forward=1` (✅ correct)
- VTI script adds route: `ip route add 10.30.0.0/16 dev vti0` (✅ correct for outbound)
- **Missing:** Source NAT or routing for return traffic to client VM

**When client VM is added:**
- Client VM (10.40.10.x) pings Azure VM (10.30.1.x)
- Packet goes: Client → strongSwan → VTI tunnel → Azure
- Return packet: Azure → VTI tunnel → strongSwan → ❓ **needs route to 10.40.10.0/24**

**Fix required (when implementing client VM):**

Option A - Use policy routing on strongSwan:
```bash
# Add to vti.sh script
ip route add 10.40.10.0/24 dev eth0  # Client subnet via internal interface
```

Option B - Use Azure UDR:
```terraform
# Not needed if using VTI correctly, but documenting for completeness
# Azure VPN Gateway auto-injects routes for address_space in Local Network Gateway
```

---

### 7. Code Quality Issues ⚠️

**Language inconsistency:**
- Line 140: Thai comment `# ICMP in VNet (สำหรับ ping ทดสอบ)`
- Line 340: Thai comment in ipsec_policy block
- **Fix:** Use English for all comments

**Misleading comment:**
- Line 340-341: Comment suggests removing ipsec_policy helps avoid mismatch
- Comment is in Thai mixed with technical terms
- **Fix:** Remove or translate to clear English with proper technical guidance

**Variable naming:**
- `vnet3_gw_cidr` vs `vnet4_vm_cidr` - inconsistent abbreviation (gw vs vm)
- Consider: `vnet3_gateway_subnet` and `vnet4_vm_subnet` for clarity

---

## Configuration Elements That Are Correct ✅

Despite the critical issues, some parts are well-configured:

1. **VPN Gateway SKU and Configuration**
   - `VpnGw1AZ` with zone redundancy (lines 82, 70)
   - Route-based VPN type (line 81)
   - Generation1 (line 83)
   - Proper ip_configuration with Dynamic allocation (lines 85-90)

2. **strongSwan VTI Tunnel Approach**
   - Uses VTI (Virtual Tunnel Interface) with mark-based routing (line 273)
   - Correct tunnel setup script at `/etc/ipsec.d/vti.sh` (lines 276-294)
   - Proper sysctl settings for IP forwarding and rp_filter (lines 296-301)
   - DPD (Dead Peer Detection) configured (lines 255-256)

3. **cloud-init Automation**
   - Proper package installation (lines 223-227)
   - File creation with correct permissions (lines 229-301)
   - Systemd service management (lines 309-310)
   - UFW firewall configuration (lines 305-308)

4. **Resource Lifecycle Management**
   - `create_before_destroy` on public IPs (lines 72, 161)
   - Proper dependency chain with Terraform resources

5. **SSH Key Management**
   - Uses `tls_private_key` resource (lines 182-185)
   - 4096-bit RSA key (line 184)
   - Sensitive output handling (line 364)

---

## Comparison to Reference Implementation

### What both-azure-vpn-gw does RIGHT that hybrid is MISSING:

| Aspect | both-azure-vpn-gw | hybrid (current) | hybrid (should be) |
|--------|-------------------|------------------|-------------------|
| **Both sides have VMs** | ✅ VM1 + VM2 | ❌ Only gateway VM | ✅ Client VM + Azure VM |
| **Test connectivity** | ✅ VM1 ↔ VM2 | ❌ Impossible | ✅ Client ↔ Azure VM |
| **Realistic topology** | ✅ Symmetric design | ❌ Asymmetric | ✅ Hybrid design |
| **Auto route injection** | ✅ Automatic | ❌ N/A (no destination) | ✅ Should be automatic |
| **NSG configuration** | ✅ Correct service tag | ❌ Wrong for VPN | ⚠️ Needs specific CIDR |

---

## Testing Impossibilities with Current Config

### What you CANNOT test right now:

1. ❌ **End-to-end connectivity** - no Azure VM to ping
2. ❌ **VPN tunnel data plane** - can establish control plane, but no traffic destination
3. ❌ **Routing validation** - no way to verify correct route injection
4. ❌ **Application-level testing** - no services to connect to
5. ❌ **IP forwarding through gateway** - no client VM to forward for
6. ❌ **Realistic hybrid scenario** - current setup is just "gateway to gateway"

### What you CAN test (limited):

1. ✅ **IPsec tunnel establishment** - if you fix cipher mismatch
2. ✅ **SSH to strongSwan VM** - but this isn't meaningful for hybrid testing
3. ✅ **Azure VPN Gateway provisioning** - infrastructure creates successfully

---

## Recommended Fix Priority

### Phase 1: Make it Work (CRITICAL) 🚨
1. **Add Azure VM subnet and VM** (VNet3)
   - Subnet: 10.30.1.0/24
   - Ubuntu VM with private IP
   - Public IP for SSH management
   - NSG allowing ICMP from 10.40.0.0/16

2. **Fix IPsec cipher mismatch**
   - Remove `ipsec_policy` block from Azure connection
   - Let auto-negotiation handle it

3. **Fix traffic selectors**
   - Change strongSwan: `leftsubnet=10.40.0.0/16`, `rightsubnet=10.30.0.0/16`

### Phase 2: Make it Realistic (IMPORTANT) ⚠️
4. **Add on-prem client VM** (VNet4)
   - New subnet: 10.40.10.0/24
   - Client VM with no public IP
   - Route table: 10.30.0.0/16 → 10.40.1.x (strongSwan VM)

5. **Enable IP forwarding on strongSwan**
   - Already in sysctl (✅)
   - Add iptables FORWARD rules
   - Add routing for client subnet

### Phase 3: Polish (NICE TO HAVE) ✨
6. **Fix NSG rules** - use explicit CIDRs
7. **Clean up code** - English comments, consistent naming
8. **Add outputs** - document expected test commands
9. **Update README** - reflect actual vs intended architecture

---

## Cost Considerations (Unchanged)

- **Azure VPN Gateway (VpnGw1AZ):** ~$190/month (zone-redundant SKU)
- **VMs (Standard_B1s):** ~$10/month each
- **Public IPs (Standard):** ~$4/month each
- **Total monthly cost:** ~$220-240 (current), ~$250-270 (with added VMs)

---

## Conclusion

The hybrid directory configuration is **architecturally incomplete** and **technically broken**. It neither:
- Works as-is (due to cipher mismatch + traffic selector issues)
- Demonstrates hybrid connectivity (due to missing VMs on both sides)

This is **not a minimal viable product** - it's a partial implementation that cannot achieve its stated goal of demonstrating hybrid VPN connectivity between on-premises and Azure environments.

### Verdict

- **Functionality:** ❌ BROKEN (will not establish working tunnel)
- **Architecture:** ❌ INCOMPLETE (missing critical components)
- **Testability:** ❌ IMPOSSIBLE (no end-to-end path)
- **Code Quality:** ⚠️ NEEDS IMPROVEMENT (mixed language, misleading comments)
- **Documentation:** ⚠️ MISLEADING (README claims functionality that doesn't exist)

**Recommendation:** Do not proceed with testing until Phase 1 and Phase 2 fixes are implemented.

---

## Appendix: Expected File Structure After Fixes

```
hybrid/
├── main.tf                 # Needs 4 new resources (2 subnets, 2 VMs)
├── variables.tf            # OK as-is
├── README.md              # Needs architecture diagram update
└── report.md              # This file
```

### New Resources Needed

1. `azurerm_subnet.vnet3_vm` - Azure VM subnet
2. `azurerm_linux_virtual_machine.vm3` - Azure test VM
3. `azurerm_subnet.vnet4_client` - On-prem client subnet
4. `azurerm_linux_virtual_machine.vm4_client` - On-prem client VM
5. `azurerm_route_table.vnet4_client_rt` - Routes to strongSwan
6. Additional NSG rules and NICs for new VMs

**Estimated effort:** 4-6 hours of Terraform development + 2-3 hours testing
