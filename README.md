# CAPEv2 • REMnux • FLARE-VM — One-Click Azure Lab

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAPT-410%2FReversingLab%2Fmain%2Fazuredeploy.json)

### How to use

1. Click the button above.
2. Fill in:
   - **clientIp** – your public IP + "/32" (e.g. `203.0.113.10/32`)
   - Linux & Windows admin usernames and passwords
   - (optional) Spot `maxPrice` cap.
3. Hit **Review + Create**. Azure builds:
   - Ubuntu Spot VM → installs **REMnux** & **CAPEv2**
   - Windows Spot VM → installs **FLARE-VM**
4. When deployment completes (~10 min), use the output IPs:
   - `ssh linuxAdmin@<LINUX_IP>` (SSH 22)
   - `mstsc /v:<WIN_IP>` (RDP 3389)
   - CAPEv2 Web UI: `http://<LINUX_IP>:8000`
5. Shut the VMs down or rely on Spot eviction to save cost.

## How it works

This template uses an **ARM deployment script** resource (`Microsoft.Resources/deploymentScripts`) to:

1. **List** all `Standard_D*` VM SKUs in your chosen region.
2. **Filter out** any SKUs restricted by subscription or zone capacity.
3. **Select** the first available SKU and output it as JSON.
4. **Feed** that SKU into both the Linux and Windows VM resources, so you never hit a `SkuNotAvailable` error.

> **VM size selection:** this template automatically picks the first available `Standard_D*` SKU in your region. If you prefer a slower or specific size, edit the Bicep and set the `hardwareProfile.vmSize` parameter manually.

### Cost @ 6 h/day (Spot)

| Item                                         | Spot $/hr | 6 h/day | 30 days |
|----------------------------------------------|-----------|--------|---------|
| Ubuntu (CAPEv2 + REMnux, Standard_D2s_v3 spot) | $0.03     | $0.18   | $5.40   |
| Windows 10 (FLARE-VM, Standard_D2s_v3 spot)   | $0.065    | $0.39   | $11.70  |
| 512 GB Premium SSD                           | —         | —       | $24.97  |
| 2 × 128 GB OS disks                          | —         | —       | $9.73   |
| Log Analytics (≤ 5 GB)                       | —         | —       | $5.00   |
| **Total**                                    |           |        | **≈ $57** |

> **Note:** Prices assume Standard_D2s_v3 spot instances at current rates. Actual cost varies by region and selected SKU; use the Azure Pricing Calculator for precise estimates.

Even at pay-as-you-go prices the lab stays ≈$108/mo, inside your $150 target.

### Security Highlights

- **Inbound**: only your IP on 22 & 3389 — no Bastion.
- **Outbound**: unrestricted by default (allows CAPEv2 to pull updates). Add egress NSG blocks or INetSim for full containment.
- **Disk encryption**: platform-managed keys by default.
- **Spot**: VMs deallocate on price spikes; data persists.
