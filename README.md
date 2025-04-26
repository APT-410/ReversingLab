# CAPEv2 • REMnux • FLARE-VM — One-Click Azure Lab

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F<YOUR-USER>%2F<YOUR-REPO>%2Fmain%2Fazuredeploy.json)

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

> **Default sizes:** `Standard_D4s_v3` (4 vCPU, 6 GiB) to ensure nested virtualization & FLARE tools run smoothly.
> Lower to `D2s_v3` in the Bicep to reduce cost if needed.

### Cost @ 6 h/day (Spot)

| Item                          | Spot $/hr | 6h/day | 30 days |
|-------------------------------|-----------|--------|---------|
| Ubuntu (CAPEv2 + REMnux)      | $0.03     | $0.18  | $5.40   |
| Windows 10 (FLARE-VM)         | $0.065    | $0.39  | $11.70  |
| 512 GB Premium SSD            | —         | —      | $24.97  |
| 2 × 128 GB OS disks           | —         | —      | $9.73   |
| Log Analytics (≤ 5 GB)        | —         | —      | $5.00   |
| **Total**                     |           |        | **≈ $57** |

Even at pay-as-you-go prices the lab stays ≈$108/mo, inside your $150 target.

### Security Highlights

- **Inbound**: only your IP on 22 & 3389 — no Bastion.
- **Outbound**: unrestricted by default (allows CAPEv2 to pull updates). Add egress NSG blocks or INetSim for full containment.
- **Disk encryption**: platform-managed keys by default.
- **Spot**: VMs deallocate on price spikes; data persists.

Enjoy your fully automated reversing lab! 🎉