# Configure the Azure provider
terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }  
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "myTFResourceGroup" {
  name     = "myTFResourceGroup"
  location = "eastus"

  tags     = {
        "Environment" = "teste atuvidade 2"
    }
}

resource "azurerm_virtual_network" "resource_vm" {
  name                = "resource_vm"
  location            = azurerm_resource_group.myTFResourceGroup.location
  resource_group_name = azurerm_resource_group.myTFResourceGroup.name
  address_space       = ["10.0.0.0/16"]

}
  
resource "azurerm_subnet" "myterraformsubnet" {
    name           = "subnet1"
    resource_group_name = azurerm_resource_group.myTFResourceGroup.name
    virtual_network_name = azurerm_virtual_network.resource_vm.name
    address_prefix = "10.0.3.0/24"
  }

resource "azurerm_public_ip" "myterraformpublicip" {
    name                         = "myPublicIP"
    location                     = azurerm_resource_group.myTFResourceGroup.location
    resource_group_name          = azurerm_resource_group.myTFResourceGroup.name
    allocation_method            = "Static"
}

resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "myNetworkSecurityGroup"
    location            = azurerm_resource_group.myTFResourceGroup.location
    resource_group_name = azurerm_resource_group.myTFResourceGroup.name

    security_rule {
        name                       = "mysql"
        priority                   = 1000
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

        security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
  }

  resource "azurerm_network_interface" "myterraformnic" {
    name                      = "myNIC"
    location                  = azurerm_resource_group.myTFResourceGroup.location
    resource_group_name       = azurerm_resource_group.myTFResourceGroup.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.myterraformsubnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id
    }
}

resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.myterraformnic.id
    network_security_group_id = azurerm_network_security_group.myterraformnsg.id
}

resource "azurerm_storage_account" "storagemysql" {
  name                     = "mysqlazure"
  resource_group_name      = azurerm_resource_group.myTFResourceGroup.name
  location                 = azurerm_resource_group.myTFResourceGroup.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_linux_virtual_machine" "myterraformvm" {
    name                  = "myVM"
    location              = azurerm_resource_group.myTFResourceGroup.location
    resource_group_name   = azurerm_resource_group.myTFResourceGroup.name
    network_interface_ids = [azurerm_network_interface.myterraformnic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "myvm"
    admin_username = "azureuser"
    admin_password = "Userpass@1"
    disable_password_authentication = false

    
    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.storagemysql.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.myTFResourceGroup ]
}

output "public_ip_address" {
  value = azurerm_public_ip.myterraformpublicip.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.myterraformvm]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "azureuser"
            password = "Userpass@1"
            host = azurerm_public_ip.myterraformpublicip.ip_address
        }
        source = "config"
        destination = "/home/azureuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "azureuser"
            password = "Userpass@1"
            host = azurerm_public_ip.myterraformpublicip.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/azureuser/config/user.sql",
            "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}

