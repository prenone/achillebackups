#!/bin/bash

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export VAR_DIR="/var/lib/achillebackups"
export ETC_DIR="/etc/achillebackups"

# Backup function
export last_backup_timestamp_file="$VAR_DIR/last_backup.timestamp"
export backup_log="$VAR_DIR/backups.log"
export include_file="$ETC_DIR/include"
export exclude_file="$ETC_DIR/exclude"
export configuration_file="$ETC_DIR/conf.sh"

do_backup() {
    restic backup $BACKUP_PATH --files-from="$include_file" --exclude-file="$exclude_file" --no-scan --tag $BACKUP_TAG --one-file-system
    echo "Finished backup at $(date) with tag '$BACKUP_TAG'" >>$"$backup_log"
}

save_timestamp() {
    # Only update last timestamp if backup is successful, this way if the backup fails it is retried without waiting.
    if [ $? -eq 0 ]; then
        echo "$(date +%s)" >"$last_backup_timestamp_file"
        echo "✅ Backup finished"
    else
        echo "❌ Error during backup"
        exit 1
    fi
}

if [ "$1" = "install" ]; then
    read -n 1 -p "Visit https://unix.stackexchange.com/questions/1067/what-directories-do-i-need-to-back-up" useless

    mkdir -p $VAR_DIR
    mkdir -p $ETC_DIR

    touch $include_file
    touch $exclude_file

    echo "0" >$last_backup_timestamp_file
    touch $backup_log

    cp "$SCRIPT_DIR/backup.sh" /usr/local/bin/achillebackups
    cp "$SCRIPT_DIR/achillebackups.service" /etc/systemd/system/
    cp "$SCRIPT_DIR/achillebackups.timer" /etc/systemd/system/
    cp "$SCRIPT_DIR/conf.sh.template" "$configuration_file"
    
    vi "$configuration_file"
    vi "$include_file"
    vi "$exclude_file"

    systemctl daemon-reload
    systemctl enable --now achillebackups.timer

    # Sometimes systemd trigger remains n/a, this seems to fix it
    systemctl restart achillebackups.timer

    echo "✅ AchilleBackups installed"
    exit 0
elif [ "$1" = "uninstall" ]; then
    systemctl stop achillebackups.timer
    systemctl disable achillebackups.timer
    systemctl stop achillebackups.service

    rm /usr/local/bin/achillebackups
    rm /etc/systemd/system/achillebackups.service
    rm /etc/systemd/system/achillebackups.timer

    systemctl daemon-reload
    systemctl reset-failed

    rm -r $VAR_DIR
    rm -r $ETC_DIR

    echo "✅ AchilleBackups uninstalled"
    exit 0
fi

# Sets restic environment variables
. "$configuration_file"

export RESTIC_REPOSITORY="rest:https://$BACKUP_USER:$BACKUP_USER_PASSWORD@$BACKUP_SERVER/$BACKUP_USER"
export RESTIC_PASSWORD="$BACKUP_ENCRYPTION_PASSWORD"
export RESTIC_COMPRESSION="max"

if [ "$1" = "init" ]; then
    restic init

    if ! [ $? -eq 0 ]; then
        exit 1
    fi

    echo "✅ Repository initialized"
fi


if [ "$1" = "automated" ]; then
    if ! test -f "$last_backup_timestamp_file"; then
        echo "❌ Execute ./backup.sh install first!"
        exit 1
    fi

    export XDG_CACHE_HOME="$VAR_DIR"

    # Parse frequency
    export number="${BACKUP_FREQUENCY%[!0-9]*}"
    export unit="${BACKUP_FREQUENCY##*[![:alpha:]]}"

    case "$unit" in
    d) export duration="$((number * 24 * 60 * 60))" ;;
    h) export duration="$((number * 60 * 60))" ;;
    m) export duration="$((number * 60))" ;;
    s) export duration="$((number))" ;;
    esac

    export last_timestamp="$(cat $last_backup_timestamp_file)"
    export current_timestamp="$(date +%s)"

    export elapsed=$(($current_timestamp - $last_timestamp))

    # If duration has elapsed do backup
    if [ $elapsed -ge $duration ]; then
        do_backup
        save_timestamp
    else
        echo "🔵 Not time to backup yet"
    fi
elif [ "$1" = "backup" ]; then
    export BACKUP_TAG="manual"
    do_backup
elif [ "$1" = "snapshots" ]; then
    restic snapshots
fi
