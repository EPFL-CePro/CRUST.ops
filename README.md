# CRUST.ops

> [!IMPORTANT]
> This has been moved to [gitlab.epfl.ch](https://gitlab.epfl.ch/cepro-it/crust.ops).

Configuration-as-code for the deployment of CRUST (CePro Requests, Unified Support Tickets), the team's ticketing tool for the shared mailbox cepro-exams@epfl.ch. CRUST is a Zammad instance running with Docker Compose on a dedicated VM. Zammad is used as is, so this is the only repository needed: it holds the Docker Compose stack, the scripts and the Ansible deployment.

## Prerequisites

- access to the Keybase team `cepro_crust`, with Keybase running and its folder mounted at `/keybase`;
- root SSH access to the prod VM, with its address set as `ansible_host` in `inventory/prod/hosts.yml`;
- `ansible-core`, only modules from `ansible.builtin` are used (no Ansible Galaxy collection).

## How it works

The deployment is a plain `ansible-playbook` run of `playbook.yml` against the `inventory/prod` inventory. The playbook:

1. loads the secrets from `secrets.yml` in the Keybase team folder;
2. installs the dependencies on the VM (Docker, Docker Compose, ...);
3. copies the Compose stacks and the scripts (`roles/crust/files/`) to `/data/crust`;
4. renders the `.env` file from `roles/crust/templates/env.j2`, with the settings of `group_vars/all/app.yml` and the secrets;
5. renders the Caddyfile (reverse proxy and TLS), then starts the containers, Caddy included.

```bash
ansible-playbook playbook.yml -i inventory/prod
```

Pushes to `main` are deployed by GitHub Actions, with the shared workflow of [CePro-Active](https://github.com/EPFL-CePro/CePro-Active) (see `.github/workflows/deploy.yml`). A manual run from the Actions tab is a dry run (`--check`) unless you untick `check_mode`.

## Tags

- `crust.setup`: installs the dependencies on the VM.
- `crust.run`: copies the stacks and the scripts, renders the `.env` and the Caddyfile, installs the TLS certificate, then starts the containers. Use this one to push changes to production.

```bash
ansible-playbook playbook.yml -i inventory/prod --tags crust.setup
ansible-playbook playbook.yml -i inventory/prod --tags crust.run
```

Add `--check` to see what would change without changing anything.

## Settings

In `group_vars/all/app.yml`:

| Variable | Description |
|---|---|
| `secrets_dir` | Folder holding `secrets.yml` (default: `/keybase/team/cepro_crust`) |
| `crust_fqdn` | DNS name of the service |
| `crust_tls_selfsigned` | `true`: temporary certificate from Caddy's own CA (browser warning). `false`: real certificate from the secrets (`crust_tls_*`) |
| `crust_tz` | Time zone |
| `crust_max_attachment_size` | Attachment size accepted by nginx |
| `crust_backup_time`, `crust_backup_hold_days` | Time and retention of the daily backup |
| `crust_nas_backup_enabled` | `true` to export the backups to the NAS share (default: `false`) |

The image versions are pinned in the Compose files themselves (see [Updating Zammad](#updating-zammad)).

## Files

In `roles/crust/files/`, copied to `/data/crust` on the VM:

- `compose.yml`: the main Compose file. It holds no service itself and only includes the two stacks below into one project (`crust`), sharing the `.env` file;
- `zammad/compose.yml`: the upstream [zammad-docker-compose](https://github.com/zammad/zammad-docker-compose) file, with fixed image versions, so that an update is a simple diff;
- `zammad/compose.override.yml`: our changes to Zammad (log rotation, nginx IPv4 only);
- `caddy/compose.yml`: the Caddy reverse proxy, with its `Caddyfile` and `certs/` next to it on the VM;
- `backup_crontab.sh`: copies the backups of the `zammad-backup` service (daily, kept `crust_backup_hold_days` days in a Docker volume) to the NAS share.

Every `docker compose` command is run from `/data/crust`, against the main file. The include needs Docker Compose 2.24 or newer.

## Reverse proxy

Caddy runs as a container of the stack (`caddy/compose.yml`) and is the only entry point: it listens on ports 80 and 443, redirects HTTP to HTTPS and forwards everything, websockets included, to the `zammad-nginx` container. Its configuration is rendered from `roles/crust/templates/Caddyfile.j2` to `/data/crust/caddy/Caddyfile`; Ansible reloads Caddy when it or the certificate changes.

There is no Let's Encrypt certificate: the VM is not reachable from the Internet. The certificate is either Caddy's own (`crust_tls_selfsigned: true`) or the one delivered by the IT (`/data/crust/caddy/certs/`).

## Updating Zammad

1. Compare `roles/crust/files/zammad/compose.yml` with the upstream file and read the release notes;
2. update the image tags in that file: Zammad, plus Elasticsearch, PostgreSQL, Redis and memcached if upstream changed them;
3. run `ansible-playbook playbook.yml -i inventory/prod --tags crust.run`, or push to `main`.

Take a VM snapshot first. Caddy is updated the same way, through its image tag in `roles/crust/files/caddy/compose.yml`.

## Secrets

Secrets are stored in `/keybase/team/cepro_crust/secrets.yml`, a plain YAML file that Keybase keeps encrypted and only shares with the team. The variables it must define are listed in `secrets.yml.example`. Edit it directly in the Keybase folder:

```bash
$EDITOR /keybase/team/cepro_crust/secrets.yml
```

With `crust_tls_selfsigned: true`, it only needs `crust_postgres_password`. To switch to the real certificate, add the `crust_tls_*` keys, set the variable to `false` and run `crust.run`.

Never copy `secrets.yml` into this repository.

## Access

The service is only meant to be reachable from the EPFL network or the VPN. Requesters never connect to it: they only exchange emails with the mailbox.
