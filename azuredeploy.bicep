@description('Your public IP in CIDR format (e.g. “203.0.113.10/32”)')
param clientIp string

// Linux creds
param linuxAdminUsername string
@secure() param linuxAdminPassword string

// Windows creds
param windowsAdminUsername string
@secure() param windowsAdminPassword string

@description('Azure region')
param location string = resourceGroup().location

// Spot settings
@description('Maximum hourly price you’ll pay (-1 = market price)')
param spotMaxPrice float = -1

// ---------- Naming helpers ----------
var prefix        = 'cape'
var vnetName      = '${prefix}-vnet'
var nsgName       = '${prefix}-nsg'
var linuxNicName  = '${prefix}-linux-nic'
var winNicName    = '${prefix}-win-nic'
var linuxPipName  = '${prefix}-linux-pip'
var winPipName    = '${prefix}-win-pip'
var linuxVmName   = '${prefix}-linux'
var winVmName     = '${prefix}-win'
var dataDiskName  = '${prefix}-datadisk'
var laName        = '${prefix}-law'

// ---------- Log Analytics ----------
resource la 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name:  laName
  location: location
  sku: { name: 'PerGB2018' }
}

// ---------- VNet ----------
resource vnet 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name:  vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.11.0.0/16' ] }
    subnets: [
      { name: 'sandbox'; properties: { addressPrefix: '10.11.1.0/24' } }
    ]
  }
}

// ---------- NSG (SSH + RDP only from your IP) ----------
resource nsg 'Microsoft.Network/networkSecurityGroups@2020-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      // SSH 22
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: clientIp
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          sourcePortRange: '*'
        }
      }
      // RDP 3389
      {
        name: 'Allow-RDP'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: clientIp
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

// ---------- Public IPs ----------
resource linuxPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: linuxPipName
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource winPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: winPipName
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// ---------- NICs ----------
resource linuxNic 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name: linuxNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ip1'
        properties: {
          subnet:               { id: vnet.properties.subnets[0].id }
          privateIPAddressVersion: 'IPv4'
          publicIPAddress:      { id: linuxPip.id }
        }
      }
    ]
    networkSecurityGroup: { id: nsg.id }
  }
}

resource winNic 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name: winNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ip1'
        properties: {
          subnet:               { id: vnet.properties.subnets[0].id }
          privateIPAddressVersion: 'IPv4'
          publicIPAddress:      { id: winPip.id }
        }
      }
    ]
    networkSecurityGroup: { id: nsg.id }
  }
}

// ---------- 512 GB Premium SSD for CAPE ----------
resource dataDisk 'Microsoft.Compute/disks@2022-03-02' = {
  name: dataDiskName
  location: location
  sku: { name: 'Premium_LRS' }
  properties: {
    creationData: { createOption: 'Empty' }
    diskSizeGB: 512
  }
}

// ---------- Ubuntu (Spot) – CAPEv2 + REMnux ----------
resource linuxVm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: linuxVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4s_v3'
      priority: 'Spot'
      evictionPolicy: 'Deallocate'
      billingProfile: { maxPrice: spotMaxPrice }
    }
    osProfile: {
      computerName:  linuxVmName
      adminUsername: linuxAdminUsername
      adminPassword: linuxAdminPassword
      linuxConfiguration: { disablePasswordAuthentication: false }
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk:  { storageAccountType: 'StandardSSD_LRS' }
      }
      dataDisks: [
        {
          lun: 1
          name: dataDisk.name
          createOption: 'Attach'
          managedDisk: { id: dataDisk.id }
        }
      ]
      imageReference: {
        publisher: 'Canonical'
        offer:     '0001-com-ubuntu-server-jammy'
        sku:       '22_04-lts'
        version:   'latest'
      }
    }
    networkProfile: { networkInterfaces: [ { id: linuxNic.id } ] }
  }
  dependsOn: [ linuxNic, dataDisk ]
}

// — Custom Script: install REMnux + CAPEv2
resource linuxExt 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = {
  parent: linuxVm
  name: 'init-tools'
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type:      'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://remnux.org/get-remnux.sh',
        'https://raw.githubusercontent.com/kevoreilly/CAPEv2/master/install.sh'
      ]
    }
    protectedSettings: {
      commandToExecute: 'bash get-remnux.sh -y && sudo bash install.sh'
    }
  }
}

// ---------- Windows (Spot) – FLARE-VM ----------
resource winVm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: winVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4s_v3'
      priority: 'Spot'
      evictionPolicy: 'Deallocate'
      billingProfile: { maxPrice: spotMaxPrice }
    }
    osProfile: {
      computerName:  winVmName
      adminUsername: windowsAdminUsername
      adminPassword: windowsAdminPassword
      windowsConfiguration: { provisionVMAgent: true }
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk:  { storageAccountType: 'StandardSSD_LRS' }
      }
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer:     'Windows-10'
        sku:       '21h2-pro'
        version:   'latest'
      }
    }
    networkProfile: { networkInterfaces: [ { id: winNic.id } ] }
  }
  dependsOn: [ winNic ]
}

// — Custom Script: install FLARE-VM
resource winExt 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = {
  parent: winVm
  name: 'init-flare'
  properties: {
    publisher: 'Microsoft.Compute'
    type:      'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/fireeye/flare-vm/master/install.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Bypass -File install.ps1 -AcceptEula -AddWindowsOptionalFeatures'
    }
  }
}

// ---------- Outputs ----------
output linuxPublicIP  string = linuxPip.properties.ipAddress
output windowsPublicIP string = winPip.properties.ipAddress
