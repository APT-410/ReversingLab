// ─────────────────────────────────────────────────────────────────────────────
// PARAMETERS
// ─────────────────────────────────────────────────────────────────────────────
@description('Your public IP in CIDR, e.g. 203.0.113.10/32')
param clientIp string

@description('Linux admin username')
param linuxAdminUsername string
@secure() @description('Linux admin password')
param linuxAdminPassword string

@description('Windows admin username')
param windowsAdminUsername string
@secure() @description('Windows admin password')
param windowsAdminPassword string

@description('Azure region (e.g. westus2)')
param location string = resourceGroup().location

@description('Max Spot price in USD/hour (-1 = current market rate)')
param spotMaxPrice int = -1

// ─────────────────────────────────────────────────────────────────────────────
// NAMING HELPERS
// ─────────────────────────────────────────────────────────────────────────────
var prefix       = 'cape'
var vnetName     = '${prefix}-vnet'
var nsgName      = '${prefix}-nsg'
var linuxPipName = '${prefix}-linux-pip'
var winPipName   = '${prefix}-win-pip'
var linuxNicName = '${prefix}-linux-nic'
var winNicName   = '${prefix}-win-nic'
var linuxVmName  = '${prefix}-linux'
var winVmName    = '${prefix}-win'
var dataDiskName = '${prefix}-datadisk'
var laName       = '${prefix}-law'

// ─────────────────────────────────────────────────────────────────────────────
// Log Analytics Workspace
// ─────────────────────────────────────────────────────────────────────────────
resource la 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name:     laName
  location: location
  sku:      { name: 'PerGB2018' }
}

// ─────────────────────────────────────────────────────────────────────────────
// VNet + Subnet
// ─────────────────────────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name:     vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.11.0.0/16' ] }
    subnets: [
      { name: 'sandbox'; properties: { addressPrefix: '10.11.1.0/24' } }
    ]
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NSG (SSH & RDP locked to your IP)
// ─────────────────────────────────────────────────────────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2020-11-01' = {
  name:     nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority:               1000
          direction:              'Inbound'
          access:                 'Allow'
          protocol:               'Tcp'
          sourceAddressPrefix:    clientIp
          sourcePortRange:        '*'
          destinationAddressPrefix: '*'
          destinationPortRange:   '22'
        }
      }
      {
        name: 'Allow-RDP'
        properties: {
          priority:               1010
          direction:              'Inbound'
          access:                 'Allow'
          protocol:               'Tcp'
          sourceAddressPrefix:    clientIp
          sourcePortRange:        '*'
          destinationAddressPrefix: '*'
          destinationPortRange:   '3389'
        }
      }
    ]
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public IPs
// ─────────────────────────────────────────────────────────────────────────────
resource linuxPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name:     linuxPipName
  location: location
  sku:      { name: 'Standard' }
  properties:{ publicIPAllocationMethod: 'Static' }
}
resource winPip 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name:     winPipName
  location: location
  sku:      { name: 'Standard' }
  properties:{ publicIPAllocationMethod: 'Static' }
}

// ─────────────────────────────────────────────────────────────────────────────
// Network Interfaces
// ─────────────────────────────────────────────────────────────────────────────
resource linuxNic 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name:     linuxNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ip1'
        properties: {
          subnet:                 { id: vnet.subnets[0].id }
          privateIPAddressVersion: 'IPv4'
          publicIPAddress:        { id: linuxPip.id }
        }
      }
    ]
    networkSecurityGroup: { id: nsg.id }
  }
}
resource winNic 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name:     winNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ip1'
        properties: {
          subnet:                 { id: vnet.subnets[0].id }
          privateIPAddressVersion: 'IPv4'
          publicIPAddress:        { id: winPip.id }
        }
      }
    ]
    networkSecurityGroup: { id: nsg.id }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Disk (512 GB Premium SSD)
// ─────────────────────────────────────────────────────────────────────────────
resource dataDisk 'Microsoft.Compute/disks@2022-03-02' = {
  name:     dataDiskName
  location: location
  sku:      { name: 'Premium_LRS' }
  properties:{
    creationData: { createOption: 'Empty' }
    diskSizeGB:   512
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ubuntu Spot VM (CAPEv2 + REMnux)
// ─────────────────────────────────────────────────────────────────────────────
resource linuxVm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name:     linuxVmName
  location: location
  properties: {
    priority:       'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: { maxPrice: spotMaxPrice }

    hardwareProfile: { vmSize: 'Standard_D4s_v3' }
    osProfile: {
      computerName:       linuxVmName
      adminUsername:      linuxAdminUsername
      adminPassword:      linuxAdminPassword
      linuxConfiguration:{ disablePasswordAuthentication: false }
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk:  { storageAccountType: 'StandardSSD_LRS' }
      }
      dataDisks: [
        {
          lun:          1
          name:         dataDisk.name
          createOption: 'Attach'
          managedDisk:  { id: dataDisk.id }
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
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomScript (install REMnux + CAPEv2)
// ─────────────────────────────────────────────────────────────────────────────
resource linuxExt 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = {
  parent:    linuxVm
  name:      'init-tools'
  location:  location
  properties:{
    publisher:               'Microsoft.Azure.Extensions'
    type:                    'CustomScript'
    typeHandlerVersion:      '2.1'
    autoUpgradeMinorVersion: true
    settings:{
      fileUris: [
        'https://remnux.org/get-remnux.sh'
        'https://raw.githubusercontent.com/kevoreilly/CAPEv2/master/install.sh'
      ]
    }
    protectedSettings:{
      commandToExecute:'bash get-remnux.sh -y && sudo bash install.sh'
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Windows Server Spot VM (FLARE-VM)
// ─────────────────────────────────────────────────────────────────────────────
resource winVm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name:     winVmName
  location: location
  properties: {
    priority:       'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: { maxPrice: spotMaxPrice }

    hardwareProfile: { vmSize: 'Standard_D4s_v3' }
    osProfile: {
      computerName:       winVmName
      adminUsername:      windowsAdminUsername
      adminPassword:      windowsAdminPassword
      windowsConfiguration:{ provisionVMAgent: true }
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk:  { storageAccountType: 'StandardSSD_LRS' }
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer:     'WindowsServer'
        sku:       '2019-Datacenter'
        version:   'latest'
      }
    }
    networkProfile:{ networkInterfaces: [ { id: winNic.id } ] }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomScript (install FLARE-VM)
// ─────────────────────────────────────────────────────────────────────────────
resource winExt 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = {
  parent:    winVm
  name:      'init-flare'
  location:  location
  properties:{
    publisher:               'Microsoft.Compute'
    type:                    'CustomScriptExtension'
    typeHandlerVersion:      '1.10'
    autoUpgradeMinorVersion: true
    settings:{
      fileUris: [
        'https://raw.githubusercontent.com/fireeye/flare-vm/master/install.ps1'
      ]
      commandToExecute:'powershell -ExecutionPolicy Bypass -File install.ps1 -AcceptEula -AddWindowsOptionalFeatures'
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────
output linuxPublicIP  string = linuxPip.properties.ipAddress
output windowsPublicIP string = winPip.properties.ipAddress
