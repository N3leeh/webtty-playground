# WebShell via https
Quick ansible playbook to install locally these requirements:
- [Wetty](https://github.com/butlerx/wetty) via docker container (listen port 3000)
- Nginx reverse proxy with TLS termination (self-signed) for Wetty
- Reconfigure SSH to use docker as an jailed environment
- Creates group `jailed` and users from `ssh_jailed_users` variable
    - users expire after `jail_account_lifetime_hours` (default 48h)
    - users with group `jailed` will connect to an unprivileged, resource-limited docker container
    - every user gets a random initial password (see [Passwörter](#passwörter))

## Usage
Entrypoint is the `./bootstrap.sh` file to install dependencies (i.e. ansible, galaxy roles and collections) and start the playbook.
Additional arguments are passed to `ansible-playbook`, e.g. `./bootstrap.sh --check --diff`.

After the workshop run `ansible-playbook teardown.yml` to remove containers, users (including home directories), image, network and generated credentials.

## Passwörter
Für jeden User in `ssh_jailed_users` wird beim ersten Lauf ein zufälliges Passwort erzeugt und auf dem Ansible-Controller unter `credentials/<user>` gespeichert (per `.gitignore` ausgeschlossen). Die erste Spalte ist das Klartext-Passwort:

```sh
for f in credentials/*; do echo "$(basename "$f"): $(cut -d' ' -f1 "$f")"; done
```

Weitere Läufe verwenden dieselben Passwörter. Für ein neues Passwort die Datei `credentials/<user>` löschen und das Playbook erneut ausführen.
Soll beim ersten Login ein Passwortwechsel erzwungen werden: `chage -d 0 <user>` (vorher testen, ob der Wechsel-Dialog über wetty funktioniert).

Das frühere Schema `<user>Start123` lässt sich über `initial_password_suffix` wieder aktivieren. Davon wird abgeraten: Benutzernamen und Suffix stehen in diesem öffentlichen Repo.

## Konfiguration
Die wichtigsten Variablen (Defaults in `roles/docker-jail/defaults/main.yml`, Workshop-Werte in `vars/jailed.yml`):

| Variable | Default | Bedeutung |
|---|---|---|
| `ssh_jailed_users` | `[]` | Login-Namen der Teilnehmenden |
| `jail_account_lifetime_hours` | `48` | Gültigkeit der Accounts (tagesgenau) |
| `jail_credentials_dir` | `credentials/` | Ablage der generierten Passwörter |
| `jail_network` | `workshop-jail` | eigenes Docker-Netz, `""` = Standard-Bridge |
| `jail_network_internal` | `true` | kein Internet aus dem Container (kein `apt install`) |
| `jail_pids_limit` | `256` | max. Prozesse pro Sitzung |
| `jail_memory` | `512m` | max. RAM pro Sitzung (ohne Swap) |
| `jail_cpus` | `1` | max. CPU-Kerne pro Sitzung |
| `jail_cap_drop_all` / `jail_capabilities` | `true` / Liste | nur nötige Linux-Capabilities |
| `jail_extra_mounts` | `[]` | zusätzliche Bind-Mounts (`quelle:ziel[:ro]`) |
| `webtty_allowed_networks` | `[]` | IP-Allowlist für die WebShell, leer = alle |
| `webtty_image` | `wettyoss/wetty:latest` | wetty-Image (Empfehlung: Version pinnen) |

## Sicherheitsmodell
- Teilnehmende landen per `ForceCommand` in einem Container. Im Container haben Mitglieder der Gruppe `users` sudo (wird für die Schnitzeljagd gebraucht). **Root im Container ist Root auf den eingehängten Verzeichnissen des Hosts** (kein User-Namespace-Remapping). Deshalb:
    - `/etc/shadow` des Hosts wird **nicht** eingehängt; der Container bekommt eine erzeugte shadow-Datei ohne Passwort-Hashes.
    - Zusätzliche Mounts (`/home/plankton`, `/etc/quallenfischen`) sind read-only.
    - Capabilities sind auf das Nötige reduziert, Prozesse/RAM/CPU begrenzt.
- Container stehen in einem eigenen, internen Netz und können sich nicht gegenseitig erreichen.
- SSH-Forwarding aller Art ist für die Gruppe `jailed` gesperrt.

### Offene Empfehlungen
- **Stärkere Isolation**: [Sysbox](https://github.com/nestybox/sysbox) als Container-Runtime oder Incus/LXD-Systemcontainer. Root im Container ist dann vom Host getrennt, und systemd/journalctl laufen im Container (passt zu den Themen von Tag 2).
- **Admin-Zugang härten**: `PermitRootLogin prohibit-password` bzw. `no` und Passwort-Login nur für die Gruppe `jailed` (`PasswordAuthentication no` + `Match Group jailed` → `PasswordAuthentication yes`). Nicht automatisch gesetzt, um niemanden auszusperren.
- **Versionen pinnen**: Galaxy-Rollen/Collections in `requirements.yml` und `webtty_image`.
- `/etc/passwd` und `/etc/group` des Hosts sind weiterhin im Container lesbar (Namen der Admin-Accounts sichtbar). Ein gefilterter Auszug wäre möglich.
- `ssh host befehl` / scp: `SSH_ORIGINAL_COMMAND` wird von sudo (`env_reset`) vermutlich verworfen.

## Docker
After the login of your students, you can execute `ansible-playbook docker-ping.yml` in order verifiy the running docker container.
This playbook can be used as an example to rollout further training materials.

`wsadm -l` lists running jail containers, `wsadm -j <container> [-r]` jumps into one (optionally as root).
