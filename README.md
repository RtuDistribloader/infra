# devops

Terraform поднимает ВМ в локальном libvirt, Ansible настраивает их: Docker +
контейнер nginx, отвечающий `IP <адрес> is alive` на порту 80.

Зависимости: qemu, libvirt (`qemu:///system`), terraform, ansible.

## Что заполнить

`terraform.tfvars` — список ВМ (он в `.gitignore`, шаблон в
`terraform.tfvars.example`):

```hcl
virtual_machines = {
  wrk1 = { cores = 2, ram_gb = 2, disk_gb = 30 }
}
```

Ключ карты — это и имя домена libvirt, и hostname, и имя хоста в инвентаре.
Остальные переменные (`base_image`, `ssh_user`, `ssh_public_key_file`) имеют
значения по умолчанию, см. `variables.tf`.

Опциональный `disk_pool` внутри элемента пока обязан быть `default` —
задавать его не нужно.

## Порядок запуска

```sh
terraform init
terraform apply          # создаёт диски, cloud-init ISO, домены; пишет ansible/inventory.ini

cd ansible
ansible-galaxy install -r requirements.yml
ansible-playbook site.yml
```

`terraform apply` ждёт DHCP-лизы каждой ВМ, так что к моменту записи инвентаря
адреса уже известны; вывести их отдельно — `terraform output vm_ips`.
Плейбук можно запускать сразу после apply: он сам дожидается SSH и завершения
cloud-init.

Проверка: `curl http://<ip>`.

## Что делает Ansible

| роль | что |
|---|---|
| `common` | hostname, timezone, базовые пакеты, отключение парольного SSH |
| `docker` | Docker CE из apt-репозитория Docker, `ssh_user` в группе `docker`, логин в приватный registry |
| `nginx` | compose-стек с `nginx:1.27-alpine`, отдающий строку с IP хоста |

Роли идемпотентны, плейбук можно прогонять повторно.

## Приватный registry (ghcr.io)

Нужен GitHub PAT (classic) с `read:packages`. Без токена шаг логина
пропускается, Docker всё равно ставится.

```sh
cd ansible
cp group_vars/vms/vault.yml.example group_vars/vms/vault.yml
$EDITOR group_vars/vms/vault.yml     # docker_registry_username / docker_registry_token
ansible-vault encrypt group_vars/vms/vault.yml
ansible-playbook site.yml --ask-vault-pass
```

Разово, без vault: `ansible-playbook site.yml -e docker_registry_username=USER -e docker_registry_token=ghp_...`

После этого `docker pull ghcr.io/OWNER/IMAGE:TAG` на ВМ работает без sudo.

## Ограничения

- cloud-init ([cloud-init/user-data.yaml.tftpl](cloud-init/user-data.yaml.tftpl))
  считается статическим: он только создаёт `ssh_user` с вашим публичным ключом.
  После его правки нужен `terraform destroy && terraform apply` — на живых ВМ
  изменения не применятся.
- Все тома (базовый образ, диски ВМ, ISO) лежат в пуле `default`; backing store
  в libvirt не работает между пулами.
- `host_key_checking` выключен в `ansible.cfg` — ВМ часто пересоздаются.
- Стейт локальный, бэкенда нет.

## Лицензия

[MIT](LICENSE).
