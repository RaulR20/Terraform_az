resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "mtc-rg" {
  name     = random_pet.rg_name.id
  location = "eastus"
  tags = {
    environment = "dev"
  }
}

resource "random_pet" "azure_virtual_network_name" {
  prefix = "vnet"
}

resource "azurerm_virtual_network" "mtc-vn" {
  name                = random_pet.azure_virtual_network_name.id
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "random_pet" "azurerm_subnet_name" {
  prefix = "sub"
}

resource "azurerm_subnet" "mtc-subnet" {
  name                 = random_pet.azurerm_subnet_name.id
  resource_group_name  = azurerm_resource_group.mtc-rg.name
  virtual_network_name = azurerm_virtual_network.mtc-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}


resource "azurerm_public_ip" "mtc-ip-lb" {
  name                = "mtc-ip-lb"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  allocation_method   = "Static"

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_lb" "mtc-lb" {
  name                = "mtc-load_b"
  location            = azurerm_resource_group.mtc-rg.location
  resource_group_name = azurerm_resource_group.mtc-rg.name

  frontend_ip_configuration {
    name                 = "publicIPAddress"
    public_ip_address_id = azurerm_public_ip.mtc-ip-lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "mtc-ip-lbpool" {
  loadbalancer_id = azurerm_lb.mtc-lb.id
  name            = "mtc-backend_addresspool"
}

resource "azurerm_network_interface" "mtc-nic" {
  count               = 2
  name                = "mtc-nic${count.index}"
  location            = azurerm_resource_group.mtc-rg.location
  resource_group_name = azurerm_resource_group.mtc-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.mtc-subnet.id
    private_ip_address_allocation = "Dynamic"
    #public_ip_address_id          = azurerm_public_ip.mtc-ip.id
  }
  tags = {
    environment = "dev"
  }
}

resource "azurerm_availability_set" "mtc-avset" {
  name                         = "mtc-availability_set"
  location                     = azurerm_resource_group.mtc-rg.location
  resource_group_name          = azurerm_resource_group.mtc-rg.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}

resource "random_pet" "azurerm_linux_virtual_machine_name" {
  prefix = "vm"
}

resource "azurerm_linux_virtual_machine" "mtc-vm" {
  count               = 2
  name                = "${random_pet.azurerm_linux_virtual_machine_name.id}${count.index}"
  resource_group_name = azurerm_resource_group.mtc-rg.name
  location            = azurerm_resource_group.mtc-rg.location
  size                = "Standard_B1s"
  availability_set_id = azurerm_availability_set.mtc-avset.id
  # admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.mtc-nic[count.index].id]
  # delete_os_disk_on_termination    = true
  # delete_data_disks_on_termination = true


  admin_ssh_key {
    username   = var.username
    public_key = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "mtc-osdisk${count.index}"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  computer_name  = "hostname"
  admin_username = var.username
}

resource "azurerm_managed_disk" "mtc-mandisk" {
  count                = 2
  name                 = "mtc-data_disk_${count.index}"
  location             = azurerm_resource_group.mtc-rg.location
  resource_group_name  = azurerm_resource_group.mtc-rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "120"
}

resource "azurerm_virtual_machine_data_disk_attachment" "mtc-data-attach" {
  count              = 2
  managed_disk_id    = azurerm_managed_disk.mtc-mandisk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.mtc-vm[count.index].id
  lun                = "10"
  caching            = "ReadWrite"
}

