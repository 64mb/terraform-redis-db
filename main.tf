resource "yandex_kms_symmetric_key" "redis_kms_key" {
  name              = "redis-kms-key"
  default_algorithm = "AES_256"
}

resource "yandex_vpc_subnet" "redis_subnet" {
  name           = "redis-subnet"
  v4_cidr_blocks = ["10.18.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = local.network_id
}

module "redis_sg" {
  source = "./module/security-group"

  name       = "redis-sg"
  network_id = local.network_id
  security_rules = {
    ingress = [
      { target = "self_security_group", from_port = 0, to_port = 65535, proto = "ANY" },
      { cidr_v4 = yandex_vpc_subnet.redis_subnet.v4_cidr_blocks, from_port = 0, to_port = 65535, proto = "ANY" },
      { cidr_v4 = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"], from_port = 0, to_port = 65535, proto = "ICMP" },
      { cidr_v4 = ["0.0.0.0/0"], from_port = 30000, to_port = 32767, proto = "TCP" },
      { cidr_v4 = local.allowed_ip, from_port = 6379, to_port = 6380, proto = "TCP" },
      { cidr_v4 = local.allowed_ip, from_port = 26379, to_port = 26380, proto = "TCP" },
    ]
  }
}

resource "random_password" "redis_password" {
  length  = 32
  special = false
}

resource "yandex_mdb_redis_cluster" "redis_cluster" {
  name        = "redis-db"
  environment = "PRODUCTION"

  network_id         = local.network_id
  security_group_ids = [module.redis_sg.id]
  persistence_mode   = "ON"
  tls_enabled        = true

  resources {
    resource_preset_id = "b1.nano"
    disk_type_id       = "network-ssd"
    disk_size          = 4
  }

  config {
    password = random_password.redis_password.result
    version  = local.redis_version

    databases = tonumber(local.redis_db_count)
  }

  host {
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.redis_subnet.id
    assign_public_ip = true
  }

  # host {
  #   zone             = "ru-central1-a"
  #   subnet_id        = yandex_vpc_subnet.redis_subnet.id
  #   assign_public_ip = true
  # }
}

resource "yandex_lockbox_secret" "redis_lockbox" {
  name       = "redis-cluster"
  kms_key_id = yandex_kms_symmetric_key.redis_kms_key.id
}

resource "yandex_lockbox_secret_version" "redis_lockbox_version" {
  secret_id = yandex_lockbox_secret.redis_lockbox.id

  entries {
    key        = "endpoint"
    text_value = yandex_mdb_redis_cluster.redis_cluster.host[0].fqdn
  }

  entries {
    key        = "password"
    text_value = random_password.redis_password.result
  }
}
