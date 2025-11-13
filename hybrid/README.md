# Hybrid VPN Configuration with Azure VPN Gateway and strongSwan VM
 
> This is not tested yet, please use as reference only. ⚠️

This Terraform project is designed to demonstrate a hybrid VPN setup between Azure and an on-premises environment using IPsec/IKEv2.
On the Azure side, it provisions a managed VPN Gateway (VpnGw1AZ) inside its own VNet and GatewaySubnet. The gateway represents a cloud-side network appliance responsible for establishing encrypted tunnels.
On the simulated on-prem side, it deploys an Ubuntu VM preconfigured with strongSwan using cloud-init, acting as a customer edge VPN device.

The primary goal is to enable private, secure routing between the two networks without manual IPsec setup on Azure. The configuration uses route-based VPN (VTI) to simplify traffic control and routing. Both sides authenticate with a pre-shared key (PSK) and negotiate modern encryption suites such as AES-GCM and ECP256.

This setup allows engineers to validate hybrid connectivity scenarios before connecting real on-prem firewalls or devices. It also helps test Azure-to-Linux interoperability, IPsec negotiation, and routing behavior in a self-contained environment.
Terraform handles all infrastructure provisioning, including VNets, subnets, public IPs, NSGs, and both connection endpoints.
The deployment runs entirely in Azure, eliminating the need for physical hardware while maintaining realistic IPsec negotiation flow.

Users can easily verify connectivity with simple pings or traceroutes from the strongSwan VM to Azure’s internal network.
The design favors clarity and reproducibility over complexity, making it ideal for learning, demonstrations, or pre-production hybrid network testing.