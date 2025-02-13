#!/bin/sh

containerize()
{
    # safety... propably useless
    if [ -z $SUDO_UID ]; then exit 1; fi
    _USER_HOME=$(eval echo "~$(id -un $SUDO_UID)")

    docker run --rm $1 \
               -v /etc/group:/etc/group:ro \
               -v /etc/passwd:/etc/passwd:ro \
               -v /etc/shadow:/etc/shadow:ro \
               -v /etc/quallenfischersong.sh:/etc/quallenfischersong.sh:ro \
               -v $_USER_HOME:$_USER_HOME \
               -v /home/plankton:/home/plankton \
               --workdir $_USER_HOME \
               --hostname $(hostname) \
               --name "$(id -nu $SUDO_UID)-$(date "+%H%M%S")" \
               --user  $(id -u $SUDO_UID):$(id -g $SUDO_UID) \
               debian-jail:latest $SSH_ORIGINAL_COMMAND
}


# must be run via sudo
if [ -z $SUDO_UID ] || [ $SUDO_UID -eq '0' ]; then
    echo "script must be run sudo and not under root"
    exit 1;
fi

# Check if TTY allocated
if tty -s; then
    containerize -it
else
    containerize -i
fi
