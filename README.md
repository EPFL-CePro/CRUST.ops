# CRUST.ops

Configuration-as-code for the deployment of CRUST (CePro Requests, Unified Support Tickets), the team's ticketing tool for the shared mailbox cepro-exams@epfl.ch. CRUST is a Zammad instance running with Docker Compose on a dedicated VM. Zammad is used as is, so this is the only repository needed: it holds the Docker Compose stack, the scripts and the Ansible deployment.

## Prerequisites

- the Ansible Vault password of the team;
- root SSH access to the prod VM, with its address set as `ansible_host` in `inventory/prod.yml`.

## How it works

The deployment is a plain `ansible-playbook` run of `playbook.yml` against `inventory/prod.yml`. Install the `ansible` package first (it includes the collections used here); with `ansible-core` alone, also run `ansible-galaxy collection install -r requirements.yml`. The playbook:

1. installs the dependencies on the VM (Docker, Docker Compose, Apache, ...);
2. copies the Compose stack and the scripts (`roles/crust/files/`) to `/data/crust`;
3. renders the `.env` file from `roles/crust/templates/env.j2`, with the settings of `group_vars/all/app.yml` and the secrets of the vault;
4. starts the containers and installs the Apache reverse proxy.

```bash
ansible-playbook -i inventory/prod.yml playbook.yml -e env=prod --vault-id @prompt
```

## Tags

- `crust.setup`: installs the dependencies on the VM.
- `crust.run`: copies the stack and the scripts, renders the `.env`, then starts the containers. Use this one to push changes to production.
- `crust.apache`: configures the Apache reverse proxy and sets up the TLS certificate (self-signed or from the vault, see `crust_tls_selfsigned`).

```bash
ansible-playbook -i inventory/prod.yml playbook.yml -e env=prod --vault-id @prompt --tags crust.setup
ansible-playbook -i inventory/prod.yml playbook.yml -e env=prod --vault-id @prompt --tags crust.run
ansible-playbook -i inventory/prod.yml playbook.yml -e env=prod --vault-id @prompt --tags crust.apache
```

## Settings

In `group_vars/all/app.yml`:

| Variable | Description |
|---|---|
| `crust_fqdn` | DNS name of the service |
| `crust_zammad_version` | Zammad image version (pinned) |
| `crust_tls_selfsigned` | `true`: temporary self-signed certificate generated on the VM (browser warning). `false`: real certificate from the vault (`crust_tls_*`) |
| `crust_tz` | Time zone |
| `crust_max_attachment_size` | Attachment size accepted by nginx |
| `crust_backup_time`, `crust_backup_hold_days` | Time and retention of the daily backup |
| `crust_nas_backup_enabled` | `true` to export the backups to the NAS share (default: `false`) |

## Files

In `roles/crust/files/`, copied to `/data/crust` on the VM:

- `docker-compose.yml`: copy of the upstream [zammad-docker-compose](https://github.com/zammad/zammad-docker-compose) file, kept unmodified so that an update is a simple diff;
- `docker-compose.override.yml`: our changes (log rotation, nginx IPv4 only);
- `backup_crontab.sh`: copies the backups of the `zammad-backup` service (daily, kept `crust_backup_hold_days` days in a Docker volume) to the NAS share.

## Updating Zammad

1. Compare `roles/crust/files/docker-compose.yml` with the upstream file and read the release notes;
2. set the new version in `crust_zammad_version` (`group_vars/all/app.yml`);
3. run `ansible-playbook -i inventory/prod.yml playbook.yml -e env=prod --vault-id @prompt --tags crust.run`.

Take a VM snapshot first.

## Secrets

Secrets are stored encrypted with Ansible Vault in `group_vars/all/vault.yml`. The variables it must define are listed in `vault.yml.example` (database password, TLS key and certificates, backup share credentials).

```bash
ansible-vault create group_vars/all/vault.yml
ansible-vault edit group_vars/all/vault.yml
```

With `crust_tls_selfsigned: true`, the vault only needs `crust_postgres_password`. To switch to the real certificate, add the `crust_tls_*` keys, set the variable to `false`, delete `/etc/ssl/certs/crust/crust-serveur.key` on the VM (the old self-signed key) and run `crust.apache`.

Never commit `vault.yml` unencrypted. The vault password is kept in the Keybase team `cepro_crust`.

## Access

The service is only meant to be reachable from the EPFL network or the VPN. Requesters never connect to it: they only exchange emails with the mailbox.
