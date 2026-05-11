# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# aiwiki :: Light · 4 ВМ для AI-агента на корпоративной вики
#
# Архитектура:
#   aiwiki-pg     192.168.1.20  PostgreSQL
#   aiwiki-n8n    192.168.1.21  n8n в Docker
#   aiwiki-ollama 192.168.1.22  Ollama в Docker
#   aiwiki-wiki   192.168.1.23  Wiki.js в Docker
#
# Все ВМ — в bridged-сети поверх моста br0 на pc-host.
# IP резервируются на роутере по MAC, прописанным ниже.

Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"
  config.vm.box_check_update = false

  # synced_folder в нашей задаче не нужен — все артефакты приходят
  # через provisioning. Отключаем, чтобы не плодить лишних маунтов.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Описание ВМ. extras — лямбда, в которой можно навесить
  # дополнительный provisioning (file/shell/etc) на конкретную машину.
  vms = [
    {
      name: "aiwiki-pg", mac: "525400AE0120", memory: 2048, cpus: 2,
      extras: ->(node) {
        node.vm.provision "file",
          source:      "configs/postgres/init.sql",
          destination: "/tmp/aiwiki-init.sql"
        node.vm.provision "shell",
          path: "provisioning/postgres.sh", privileged: true
      }
    },
    { name: "aiwiki-n8n",    mac: "525400AE0121", memory: 2048, cpus: 2 },
    { name: "aiwiki-ollama", mac: "525400AE0122", memory: 6144, cpus: 4 },
    { name: "aiwiki-wiki",   mac: "525400AE0123", memory: 2048, cpus: 2 },
  ]

  vms.each do |vm|
    config.vm.define vm[:name] do |node|
      node.vm.hostname = vm[:name]

      # Bridged-сеть на br0. IP назначается DHCP-резервом на роутере по MAC.
      node.vm.network "public_network",
        dev:  "br0",
        type: "bridge",
        mac:  vm[:mac]

      node.vm.provider :libvirt do |lv|
        lv.memory       = vm[:memory]
        lv.cpus         = vm[:cpus]
        lv.cpu_mode     = "host-passthrough"
        lv.machine_type = "q35"
      end

      # Базовая инициализация — общая для всех ВМ
      node.vm.provision "shell",
        path: "provisioning/common.sh", privileged: true

      # Доп. provisioning, специфичный для конкретной ВМ
      vm[:extras].call(node) if vm[:extras]
    end
  end
end
