# WebShell via https
Quick ansible playbook to install locally these requirements:
- [Wetty](https://github.com/butlerx/wetty) via docker container (listen port 3000)
- Nginx reverse proxy with TLS termination (self-signed) for Wetty
- Reconfigure SSH to use docker as an jailed environment
- Creates group `jailed` and users from `ssh_jailed_users` variable
    - users expire within 24 hours
    - users with group `jailed` will connect to unprivileged docker container
    - Set inital password of $USERNAME concat with initial_password_suffix variable (i.e. `maxStart123`).

## Usage
Entrypoint is the `./bootstrap.sh` file to install dependencies (i.e. ansible and galaxy roles) and start the playbook.