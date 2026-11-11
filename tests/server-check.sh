#!/usr/bin/env bash
#
# Schnelltest auf dem Workshop-Server NACH dem Ausrollen (als root):
#   sudo bash tests/server-check.sh [teilnehmer]
#
# Prüft die Kette Browser -> nginx -> wetty -> SSH -> Jail, ohne etwas zu
# verändern. Ohne Argument wird der erste User der Gruppe jailed genommen.

set -u
ok=0; fail=0
pass() { printf '  \033[32mOK\033[0m     %s\n' "$*"; ok=$((ok+1)); }
bad()  { printf '  \033[31mFEHLER\033[0m %s\n' "$*"; fail=$((fail+1)); }
check() { local text=$1; shift; if "$@" >/dev/null 2>&1; then pass "$text"; else bad "$text"; fi; }

user=${1:-$(getent group jailed | cut -d: -f4 | cut -d, -f1)}
[ -z "$user" ] && user=$(awk -F: -v g="$(getent group jailed | cut -d: -f3)" '$4==g {print $1; exit}' /etc/passwd)

echo "== Dienste"
for svc in docker nginx webtty; do check "Dienst $svc läuft" systemctl is-active --quiet "$svc"; done
check "Dienst ssh läuft" sh -c 'systemctl is-active --quiet ssh || systemctl is-active --quiet sshd'
check "wetty-Container läuft" sh -c 'docker ps --format "{{.Names}}" | grep -q webtty'

echo "== Web (nginx -> wetty)"
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/)
case $code in
    301) pass "http:// leitet auf https:// um (webtty_tls: selfsigned)"
         if curl -sk https://127.0.0.1/ | grep -qi wetty; then pass "https:// liefert die wetty-Seite"; else bad "https:// liefert NICHT die wetty-Seite"; fi ;;
    200) if curl -s http://127.0.0.1/ | grep -qi wetty; then pass "http:// liefert die wetty-Seite (webtty_tls: none)"; else bad "http:// liefert NICHT die wetty-Seite"; fi ;;
    401) pass "Basic-Auth aktiv (401 ohne Workshop-Passwort)" ;;
    *)   bad "http:// antwortet mit $code" ;;
esac
check "wetty ist NICHT öffentlich erreichbar (Port 3000 nur auf der Docker-Bridge)" \
    sh -c '! ss -ltn | grep -E "(0\.0\.0\.0|\*|\[::\]):3000 "'

echo "== SSH für Teilnehmende ($user)"
if [ -z "$user" ]; then
    bad "kein User in der Gruppe jailed gefunden"
else
    subnet=$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Subnet}}')
    wetty_ip=$(echo "$subnet" | sed -E 's#\.0/[0-9]+$#.2#')
    pw_wetty=$(sshd -T -C "user=$user,host=wetty,addr=$wetty_ip" 2>/dev/null | awk '/^passwordauthentication/ {print $2}')
    pw_extern=$(sshd -T -C "user=$user,host=extern,addr=198.51.100.1" 2>/dev/null | awk '/^passwordauthentication/ {print $2}')
    fc=$(sshd -T -C "user=$user,host=wetty,addr=$wetty_ip" 2>/dev/null | awk '/^forcecommand/ {$1=""; print}')
    [ "$pw_wetty" = yes ] && pass "Passwort-Login aus dem wetty-Netz ($subnet) erlaubt" || bad "Passwort-Login aus dem wetty-Netz ist AUS - Login über den Browser unmöglich"
    [ "$pw_extern" = no ] && pass "Passwort-Login von außen gesperrt" || bad "Passwort-Login von außen ist erlaubt"
    case $fc in *containerize.sh*) pass "Login landet zwingend im Container (ForceCommand)";; *) bad "kein ForceCommand für $user";; esac
    check "$user ist in den Gruppen jailed und users" sh -c "id -nG '$user' | grep -qw jailed && id -nG '$user' | grep -qw users"
    check "$user ist NICHT in der Gruppe docker/sudo" sh -c "! id -nG '$user' | grep -qwE 'docker|sudo'"
fi

echo "== Jail"
check "Jail-Image debian-jail vorhanden" docker image inspect debian-jail:latest
check "/usr/local/containerize.sh vorhanden" test -x /usr/local/containerize.sh

echo; echo "Ergebnis: $ok ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
