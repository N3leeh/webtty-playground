# WebShell via http(s)
Quick ansible playbook to install locally these requirements:
- [Wetty](https://github.com/butlerx/wetty) via docker container (listen port 3000, only on the docker bridge)
- Nginx reverse proxy for Wetty: `http://<server-ip>` (redirect to https with a self-signed certificate, or plain http)
- Reconfigure SSH to use docker as an jailed environment
- Creates group `jailed` and users from `ssh_jailed_users` variable
    - users expire after `jail_account_lifetime_hours` (default 48h)
    - users with group `jailed` will connect to an unprivileged, resource-limited docker container
    - passwords random or composed from parts like user+suffix+number+special (see [Passwörter](#passwörter))

## Usage
Entrypoint is the `./bootstrap.sh` file to install dependencies (i.e. ansible, galaxy roles and collections) and start the playbook.
Additional arguments are passed to `ansible-playbook`, e.g. `./bootstrap.sh --check --diff`.

After the workshop run `ansible-playbook teardown.yml` to remove containers, users (including home directories), image, network and generated credentials.

## Workshop-Server bei einem Hoster (z.B. Hetzner)

Ablauf im Browser: `http://<IP>` → nginx (80/443) → wetty (nur intern auf der Docker-Bridge) → SSH auf den Server (Docker-Netz) → Jail-Container der Person.

1. Server mit **Debian 13** und SSH-Key für die Admins bestellen.
2. **Firewall beim Hoster** (z.B. Hetzner Cloud Firewall), eingehend:
    - TCP 80 und 443 von überall (Teilnehmende)
    - TCP 22 nur von der eigenen IP (Admins)
3. Auf dem Server: Repo klonen, Teilnehmende in `vars/jailed.yml` eintragen, `./bootstrap.sh` ausführen.
4. Passwörter austeilen (siehe unten), Teilnehmende öffnen `http://<IP>`.

**Browser-Warnung:** Mit `webtty_tls: "selfsigned"` (Standard, `vars/nginx.yml`) leitet `http://<IP>` auf `https://<IP>` um. Weil das Zertifikat selbst ausgestellt ist, warnt der Browser beim ersten Aufruf einmal („Erweitert → Risiko akzeptieren“). Wer das nicht möchte, setzt `webtty_tls: "none"`: Dann läuft alles über `http://<IP>`, Passwörter gehen aber unverschlüsselt über das Netz.
Tipp für ein Zertifikat ohne Warnung: Über [sslip.io](https://sslip.io) hat jede IP einen Namen (`203-0-113-10.sslip.io`), damit lässt sich ein Let's-Encrypt-Zertifikat holen (`apt install certbot python3-certbot-nginx && certbot --nginx -d 203-0-113-10.sslip.io`).

**Warum das vorher nicht ging:** Viele Hoster (z.B. Hetzner über cloud-init) schalten den SSH-Login per Passwort global ab (`PasswordAuthentication no` in `/etc/ssh/sshd_config.d/50-cloud-init.conf`). wetty meldet sich aber per Passwort an. Jetzt erlaubt `/etc/ssh/sshd_config.d/10-workshop.conf` den Passwort-Login **nur für die Gruppe `jailed` und nur aus dem Docker-Netz von wetty**.

### Was schützt wen (bewusst einfach gehalten)
| Risiko | Schutz |
|---|---|
| Passwort-Raten über SSH aus dem Internet | Teilnehmende können sich über Port 22 von außen **gar nicht** anmelden (kein Passwort, keine Keys). Admins nur per Key. |
| Passwort-Raten über die Web-Seite | pro Person unterschiedliche Passwörter (zufällige Zahl/Sonderzeichen oder komplett zufällig), `MaxAuthTries 6`; optional `webtty_basic_auth: true` (gemeinsames Workshop-Passwort vor der Login-Seite) oder `webtty_allowed_networks` (z.B. nur Uni-Netz) |
| Teilnehmende untereinander | eigener Container pro Sitzung, nur das eigene Home eingehängt, keine Verbindung zwischen Containern, kein Internet, Limits für CPU/RAM/Prozesse, max. 3 Sitzungen pro Person (`jail_max_sessions_per_user`) |
| Zugriff auf den Server selbst | kein Shell-Zugang auf dem Host (`ForceCommand`), keine Passwort-Hashes im Container, keine SSH-Weiterleitungen |
| Nicht abgedeckt | Plattenplatz: wer sein Home vollschreibt, füllt die Platte für alle. Für eine Wegwerf-VM akzeptiert. |

**Achtung fail2ban/ufw:** Alle Logins über wetty kommen von derselben Docker-IP. fail2ban auf sshd würde nach ein paar falschen Passwörtern **alle** aussperren (falls doch genutzt: `ignoreip = 172.16.0.0/12`). Eine Host-Firewall (ufw/nftables) muss Port 22 von der Docker-Bridge erlauben.

## Passwörter
Zwei Modi, einzustellen in `vars/jailed.yml`:

- **`jail_password_mode: "pattern"`** (so voreingestellt): Das Passwort wird aus Bausteinen zusammengesetzt, z.B. `maxStart482#`.
  ```yaml
  jail_password_pattern: ["user", "suffix", "number", "special"]   # Reihenfolge frei wählbar
  jail_password_suffix: "Start"
  jail_password_number: ""    # "" = pro Person zufällig (3 Stellen), oder fest z.B. "2026"
  jail_password_special: ""   # "" = pro Person zufällig aus !?#+-.@, oder fest z.B. "!"
  ```
  Bausteine: `user` (max), `User` (Max), `suffix`, `number`, `special`; alles andere wird wörtlich übernommen (z.B. `["User", "-", "number"]`).
  **Hinweis:** Sind Zahl und Sonderzeichen fest, steht das komplette Schema in diesem öffentlichen Repo und ist für jeden erratbar. Dann besser `webtty_basic_auth` oder `webtty_allowed_networks` aktivieren.
- **`jail_password_mode: "random"`**: zufälliges 12-stelliges Passwort pro Person.

In beiden Fällen liegt das Klartext-Passwort danach auf dem Ansible-Controller unter `credentials/<user>` (per `.gitignore` ausgeschlossen, erste Spalte):

```sh
for f in credentials/*; do echo "$(basename "$f"): $(cut -d' ' -f1 "$f")"; done
```

Weitere Läufe verwenden dieselben Passwörter. Für ein neues Passwort (oder nach einem Wechsel des Modus) die Dateien `credentials/<user>` bzw. `credentials/.<user>.*` löschen und das Playbook erneut ausführen.
Soll beim ersten Login ein Passwortwechsel erzwungen werden: `chage -d 0 <user>` (vorher testen, ob der Wechsel-Dialog über wetty funktioniert).

## Konfiguration
Die wichtigsten Variablen (Defaults in `roles/docker-jail/defaults/main.yml`, Workshop-Werte in `vars/jailed.yml`):

| Variable | Default | Bedeutung |
|---|---|---|
| `ssh_jailed_users` | `[]` | Login-Namen der Teilnehmenden |
| `jail_account_lifetime_hours` | `48` | Gültigkeit der Accounts (tagesgenau) |
| `jail_credentials_dir` | `credentials/` | Ablage der Passwörter (Klartext) |
| `jail_password_mode` | `random` (Workshop: `pattern`) | Zufallspasswort oder aus Bausteinen zusammengesetzt |
| `jail_network` | `workshop-jail` | eigenes Docker-Netz, `""` = Standard-Bridge |
| `jail_network_internal` | `true` | kein Internet aus dem Container (kein `apt install`) |
| `jail_pids_limit` | `256` | max. Prozesse pro Sitzung |
| `jail_memory` | `512m` | max. RAM pro Sitzung (ohne Swap) |
| `jail_cpus` | `1` | max. CPU-Kerne pro Sitzung |
| `jail_cap_drop_all` / `jail_capabilities` | `true` / Liste | nur nötige Linux-Capabilities |
| `jail_extra_mounts` | `[]` | zusätzliche Bind-Mounts (`quelle:ziel[:ro]`) |
| `webtty_allowed_networks` | `[]` | IP-Allowlist für die WebShell, leer = alle |
| `webtty_image` | `wettyoss/wetty:latest` | wetty-Image (Empfehlung: Version pinnen) |
| `jail_user_extra_groups` | `['users']` | Zusatzgruppen der Teilnehmenden (für sudo im Container nötig) |
| `jail_privileged_groups` | `docker, sudo, ...` | aus diesen Gruppen werden Teilnehmende entfernt |
| `jail_motd_template` | `workshop-motd.j2` | Login-Nachricht, `""` = keine |
| `jail_max_sessions_per_user` | `3` | gleichzeitige Sitzungen pro Person, `0` = unbegrenzt |
| `jail_wetty_subnet_override` | `""` | Netz für den Passwort-Login, `""` = Docker-Bridge automatisch |
| `webtty_tls` | `selfsigned` | `selfsigned` (http→https) oder `none` (nur http) - in `vars/nginx.yml` |
| `webtty_basic_auth` | `false` | gemeinsames Workshop-Passwort vor der Login-Seite (`credentials/web-zugang`) |
| `webtty_public_address` | IPv4 des Servers | Adresse im Zertifikat |

## Sicherheitsmodell
- Teilnehmende landen per `ForceCommand` in einem Container. Im Container haben Mitglieder der Gruppe `users` sudo (wird für die Schnitzeljagd gebraucht). **Root im Container ist Root auf den eingehängten Verzeichnissen des Hosts** (kein User-Namespace-Remapping). Deshalb:
    - `/etc/shadow` des Hosts wird **nicht** eingehängt; der Container bekommt eine erzeugte shadow-Datei ohne Passwort-Hashes.
    - Zusätzliche Mounts (`/home/plankton`, `/etc/quallenfischen`) sind read-only.
    - Capabilities sind auf das Nötige reduziert, Prozesse/RAM/CPU begrenzt.
- Container stehen in einem eigenen, internen Netz und können sich nicht gegenseitig erreichen.
- SSH-Forwarding aller Art ist für die Gruppe `jailed` gesperrt; Passwort-Login nur aus dem wetty-Netz.

### Offene Empfehlungen
- **Stärkere Isolation**: [Sysbox](https://github.com/nestybox/sysbox) als Container-Runtime oder Incus/LXD-Systemcontainer. Root im Container ist dann vom Host getrennt, und systemd/journalctl laufen im Container (passt zu den Themen von Tag 2).
- **Admin-Zugang**: Das Playbook ändert den Login der Admins nicht (um niemanden auszusperren). Bei Hostern mit SSH-Key ist Passwort-Login für Admins meist schon aus; sonst `PasswordAuthentication no` global setzen - Teilnehmende können sich über wetty trotzdem anmelden.
- **Versionen pinnen**: Galaxy-Rollen/Collections in `requirements.yml` und `webtty_image`.
- `/etc/passwd` und `/etc/group` des Hosts sind weiterhin im Container lesbar (Namen der Admin-Accounts sichtbar). Ein gefilterter Auszug wäre möglich.
- `ssh host befehl` / scp: `SSH_ORIGINAL_COMMAND` wird von sudo (`env_reset`) vermutlich verworfen.

## Tests und Pipeline
`.github/workflows/ci.yml` läuft bei jedem Push und Pull Request:

- **Lint**: yamllint (`.yamllint`), shellcheck, hadolint für das Dockerfile, ansible-lint (`.ansible-lint`, zunächst nicht blockierend)
- **Syntax**: `ansible-playbook --syntax-check` für alle Playbooks
- **Jail-Integrationstest** (`tests/jail-test.yml`): baut das echte Jail-Image, legt einen Test-Account an und startet über `containerize.sh` echte Container - genau wie beim SSH-Login. Geprüft wird u.a.: richtiger User, Gruppen `jailed users`, sudo funktioniert, **keine Passwort-Hashes** in `/etc/shadow` im Container, `mknod` verboten (Capabilities), kein Default-Route (internes Netz), Prozesslimit, Read-only-Mounts, Login-Nachricht. Danach wird `containerize.sh` mit shellcheck geprüft.

Lokal auf einem Test-Server (nicht während eines Workshops!):
```sh
ansible-playbook -i localhost, -c local tests/jail-test.yml
```

Nicht automatisch getestet: nginx, wetty und die sshd-Konfiguration (brauchen einen vollständigen Server).

## Login-Nachricht
Bei jedem interaktiven Login zeigt `containerize.sh` die Nachricht aus `/etc/workshop-motd` an (Template `roles/docker-jail/templates/workshop-motd.j2`, `@USER@` wird durch den Login-Namen ersetzt). Abschalten mit `jail_motd_template: ""`.

## Docker
After the login of your students, you can execute `ansible-playbook docker-ping.yml` in order verifiy the running docker container.
This playbook can be used as an example to rollout further training materials.

`wsadm -l` lists running jail containers, `wsadm -j <container> [-r]` jumps into one (optionally as root).
