#!/bin/bash
# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE Linux GmbH, Nuremberg, Germany.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE Linux GmbH.
#
# ------------------------------------------------------------------------------
#
# HANA cluster debug and test script
# Ilya Manyugin <imanyugin@suse.com>
# Version: 1.3

# HANA 
SID="PRD"
INO="00"
PRIM_HNAME="hana01"                 # host name of the primary
SEC_HNAME="hana02"                  # host name of the secondary
PRIM_NAME="NUREMBERG"               # site name of the primary
SEC_NAME="PRAGUE"                   # site name of the secondary
VIP='192.168.101.100'               # Virtual IP
DB_USER='SYSTEM'
DB_PASS='Qwerty1234'
REPO_USER="MY_REPO_IMPORT_USER"     # Repo user for the SRTAKEOVER key
DB_PORT="3${INO}15"                 # DB port for the first tenant
DB_PORT_SYSTEM="3${INO}13"          # DB port for the SYSTEMDB
# Names of the cluster resources
HANA_RSC="msl_SAPHana_${SID}_HDB${INO}"
HANAT_RSC="cln_SAPHanaTopology_${SID}_HDB${INO}"
VIP_RSC="rsc_ip_${SID}_HDB${INO}"
ADMUSER="$(echo "$SID" | tr '[:upper:]' '[:lower:]')adm"
UPD_LOCATION="/hana/upd/DATA_UNITS/HDB_LCM_LINUX_X86_64/"


# (see https://help.sap.com/viewer/6b94445c94ae495c83a19646e7c3fd56/2.0.01/en-US/ee3fd9a0c2e74733a74e4ad140fde60b.html)
# Some great triple-quoting in BASH follows...
REPO_USER_SQL=(
"CREATE USER ${REPO_USER} PASSWORD ${DB_PASS};"
"GRANT EXECUTE ON SYS.REPOSITORY_REST TO ${REPO_USER};"
"GRANT REPO.READ ON \\\\\\\".REPO_PACKAGE_ROOT\\\\\\\" TO ${REPO_USER};"
"GRANT REPO.IMPORT TO ${REPO_USER};"
"GRANT SELECT ON _SYS_REPO.DELIVERY_UNITS  TO ${REPO_USER};"
"GRANT REPO.ACTIVATE_IMPORTED_OBJECTS  ON \\\\\\\".REPO_PACKAGE_ROOT\\\\\\\" TO ${REPO_USER};"
)

function print_help(){
    cat <<-EOF
Supported commands:

* HANA
  ----
  start       start HANA
  stop        stop HANA
  info        show HANA processes
  kill        kill all HANA processes
  version     show HANA version
  overview    show HANA overview
  dummy       select DUMMY from the DB using the VIP
  ctemp       create table ZZZ_MYTEMP
  stemp       select from table ZZZ_MYTEMP
  wtemp       insert into table ZZZ_MYTEMP
  upgrade     upgrade HANA
  srtakeover1  create the SRTAKEOVER user store key and a DB user (HANA 1.0, 2.0 SPS0)
  srtakeover2  create the SRTAKEOVER user store key and a DB user (HANA 2.0 SPS1+)
  srtakeover-check  check the key and the DB user (locally)
  copy-keys   copy the PKI SSFS data and key files (from this node to the other)
  uninstall   uninstall HANA
  console     HDB console SR info
  landscape   Landscape Host Configuration
  hdbsql      Call HDBSQL to the SDC HANA (localhost)
  hdbsql-sys  Call HDBSQL to the SYSTEMDB (MDC, localhost)

* HANA system replication
  -----------------------
  backup-sdc  create initial HANA backup (single container)
  backup-mdc  create initial HANA backup (multiple tenants, one by one)
  backup-mdcf create initial HANA backup (multiple tenants, FOR FULL SYSTEM)
  enable      enable SR on this host
  register    register this site as secondary
  disable     disable system replication
  unregister  unregister secondary
  cleanup     Force clean-up of SR state (ACHTUNG!)
  state       HANA nameserver state
  state-c     HANA nameserver state (sapcontrol)
  status      show SR status (sync state)
  status-c    show SR status (sync state) (sapcontrol)
  takeover    take over to the current node
  overview    print HANA system overview

* Cluster
  -------
  m           run crm_monitor once
  mm          run crm_mon continuously
  mon         enable maintenance of RAs
  moff        disable maintenance of RAs
  cup         clean up the RAs
  mig         force migrate vIP resource
  fip         find vIP resource

* System
  ------
  blockt      block all TCP ports except 22

# add anything after the command name to suppress execution
EOF
}

function echo_cmd(){
    if [[ -t 1 ]]; then echo -e "\e[33m\e[1m> $1\e[0m"; else echo "> $1"; fi 
}

function echo_green(){
    if [[ -t 1 ]]; then echo -e "\e[1m\e[32m$1\e[0m"; else echo "$1"; fi 
}

function echo_red(){
    if [[ -t 1 ]]; then echo -e "\e[1m\e[31m$1\e[0m"; else echo "$1"; fi
}

function echo_yellow(){
    if [[ -t 1 ]]; then echo -e "\e[1m\e[33m$1\e[0m"; else echo "$1"; fi
}

function echo_retcode(){
    if [[ -t 1 ]]; then
        if [[ $1 -eq 0 ]]; then
            echo_green ">> Return code: $1"
        else
            echo_red ">> Return code: $1"
        fi
    else
        echo ">> Return code: $1"
    fi
}

function execute_and_echo(){
    local cmd=${1:-false}
    local mode=${2:-execute}

    echo_cmd "$cmd"
    if [[ $mode == "execute" ]]; then
        eval "$cmd"
        rc=$?
        echo_retcode "$rc"
    fi
    return $rc
}

# TODO: check if it is port xx13 or xx15
function prepare_sql_statement_sdc(){
    # echo "su -lc \"hdbsql -j -u $DB_USER -n ${VIP}:${DB_PORT} -p $DB_PASS \\\"$1\\\"\" $ADMUSER"
    echo "su -lc \"hdbsql -j -u $DB_USER -n ${VIP}:${DB_PORT} -p $DB_PASS \\\"$1\\\"\" $ADMUSER"
}

function prepare_sql_statement(){
    local db_host db_port tenant_db statement
    if [[ $# -lt 4 ]]; then
        echo_red "Wrong usage of function prepare_sql_statement"
        exit 1
    fi
    db_host=$1
    db_port=$2
    tenant_db=$3
    statement=$4
    hdbsql_opts=${5:-}
    echo "su -lc \"hdbsql ${hdbsql_opts} -j -d ${tenant_db} -u ${DB_USER} -n ${db_host}:${db_port} -p $DB_PASS \\\"${statement}\\\"\" $ADMUSER"
}

function prep_sql_multiline(){
    echo "su -lc 'hdbsql -m -j -u $DB_USER -n ${VIP}:${DB_PORT} -p $DB_PASS \"$1\"' $ADMUSER"
}

function enable_primary(){
    # provide $1 to supress execution
    local loc_node
    loc_node=$(hostname -s)
    local loc_site
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        loc_site=$PRIM_NAME
    else
        loc_site=$SEC_NAME
    fi
    execute_and_echo "su -lc 'hdbnsutil -sr_enable --name=${loc_site}' $ADMUSER" "$1"
}

function disable_primary(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_disable' $ADMUSER" "$1"
}

function register_secondary(){
    # provide $1 to supress execution
    local loc_node
    loc_node=$(hostname -s)
    local loc_site
    local rem_node
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        loc_site=$PRIM_NAME
        rem_node=$SEC_HNAME
    else
        loc_site=$SEC_NAME
        rem_node=$PRIM_HNAME
    fi
    execute_and_echo "su -lc 'hdbnsutil -sr_register --remoteHost=${rem_node} --remoteInstance=${INO} --replicationMode=sync --operationMode=delta_datashipping --name=${loc_site}' $ADMUSER" "$1"
}

function unregister_secondary(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_unregister' $ADMUSER" "$1"
}

function sr_state(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_state' $ADMUSER" "$1"
}

function sr_cleanup(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_cleanup --force' $ADMUSER" "$1"
}

function sr_state_control(){
    # provide $1 to supress execution
    local cmd
    execute_and_echo "su -lc 'hdbnsutil -sr_state --sapcontrol=1' $ADMUSER" "$1"
}

function sr_status(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'HDBSettings.sh systemReplicationStatus.py' $ADMUSER" "$1"
}

function sr_status_control(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'HDBSettings.sh systemReplicationStatus.py --sapcontrol=1' $ADMUSER" "$1"
}

function cluster_maintenance(){
    # provide $2 to supress execution
    local mode=$1
    if [[ $mode == "on" ]]; then
        execute_and_echo "crm resource maintenance $HANA_RSC" "$2"
        execute_and_echo "crm resource maintenance $HANAT_RSC" "$2"
        execute_and_echo "crm resource maintenance $VIP_RSC" "$2"
    elif [[ $mode == "off" ]]; then
        execute_and_echo "crm resource maintenance $HANA_RSC off" "$2"
        execute_and_echo "crm resource maintenance $HANAT_RSC off" "$2"
        execute_and_echo "crm resource maintenance $VIP_RSC off" "$2"
    else
        echo_cmd "WRONG MODE=$mode"
        exit 1
    fi
}

function resource_cleanup(){
    # provide $1 to supress execution
    execute_and_echo "crm resource cleanup $HANA_RSC" "$1"
    execute_and_echo "crm resource cleanup $HANAT_RSC" "$1"
    execute_and_echo "crm resource cleanup $VIP_RSC" "$1"
}

function migrate_vip(){
    # provide $1 to supress execution
    local loc_node rem_node
    loc_node=$(hostname -s)
    local loc_rc rem_rc
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        rem_node="$SEC_HNAME"
    else
        rem_node="$PRIM_HNAME"
    fi
    execute_and_echo "crm_resource --resource $VIP_RSC --force-check &>/dev/null" "$1"
    loc_rc=$?
    execute_and_echo "ssh $rem_node 'crm_resource --resource $VIP_RSC --force-check &>/dev/null'" "$1"
    rem_rc=$?
    if [[ $loc_rc -eq 0 ]]; then
        echo_green "Resouce $VIP_RSC is running locally"
        execute_and_echo "crm_resource --resource $VIP_RSC --force-stop" "$1"
        execute_and_echo "ssh $rem_node 'crm_resource --resource $VIP_RSC --force-start'" "$1"
    elif [[ $rem_rc -eq 0 ]]; then
        echo_green "Resource $VIP_RSC is running remotely"
        execute_and_echo "ssh $rem_node 'crm_resource --resource $VIP_RSC --force-stop'" "$1"
        execute_and_echo "crm_resource --resource $VIP_RSC --force-start" "$1"
    else
        echo_red "Resource $VIP_RSC is not running anywhere!"
        exit 1
    fi
}

function find_vip(){
    # provide $1 to supress execution
    local loc_node rem_node
    loc_node=$(hostname -s)
    local loc_rc rem_rc
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        rem_node="$SEC_HNAME"
    else
        rem_node="$PRIM_HNAME"
    fi
    execute_and_echo "crm_resource --resource $VIP_RSC --force-check &>/dev/null" "$1"
    loc_rc=$?
    execute_and_echo "ssh $rem_node 'crm_resource --resource $VIP_RSC --force-check &>/dev/null'" "$1"
    rem_rc=$?
    if [[ $loc_rc -eq 0 ]]; then
        echo_green "Resouce $VIP_RSC is running locally on node $loc_node"
    elif [[ $rem_rc -eq 0 ]]; then
        echo_green "Resource $VIP_RSC is running remotely on node $rem_node"
    else
        echo_red "Resource $VIP_RSC is not running anywhere!"
        exit 1
    fi
}

function hdb_command(){
    # provide $2 to supress execution
    local func=${1:-info}
    execute_and_echo "su -lc 'HDB $func' $ADMUSER" "$2"
}

function select_dummy(){
    # provide $1 to supress execution
    local cmd
    cmd=$(prepare_sql_statement "$VIP" "$DB_PORT" "$SID" "SELECT * FROM DUMMY")
    execute_and_echo "$cmd" "$1"
}

function select_temp(){
    # provide $1 to supress execution
    local cmd
    cmd=$(prepare_sql_statement "$VIP" "$DB_PORT" "$SID" "SELECT * FROM ZZZ_MYTEMP")
    execute_and_echo "$cmd" "$1"
}

function write_temp(){
    # provide $1 to supress execution
    local val cmd
    val=$(date +'%F %T.%N')
    echo_yellow "Inserting value '$val'"
    cmd=$(prepare_sql_statement "$VIP" "$DB_PORT" "$SID" "INSERT INTO ZZZ_MYTEMP VALUES('WOOHOO $val');")
    execute_and_echo "$cmd" "$1"
}

function create_temp(){
    # provide $1 to supress execution
    local cmd
    cmd=$(prepare_sql_statement "$VIP" "$DB_PORT" "$SID" "CREATE TABLE ZZZ_MYTEMP (fld VARCHAR(255));")
    execute_and_echo "$cmd" "$1"
}

function hana_take_over(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_takeover' $ADMUSER" "$1"
}

# Create the SRTAKEOVER user store key
# Create a DB user and grant necessary privileges
function srtakeover_user_hana_2_sps1(){
    # provide $1 to supress execution
    local line cmd
    echo_green "This creates a key for HANA 2.0 SPS01+ with port 3xx13. Use 3xx15 for prior versions."
    execute_and_echo "su -lc 'hdbuserstore set SRTAKEOVER ${VIP}:${DB_PORT_SYSTEM} ${REPO_USER} ${DB_PASS}' $ADMUSER" "$1"
    for line in "${REPO_USER_SQL[@]}"; do
        # cmd=$(prepare_sql_statement "$VIP" "$DB_PORT_SYSTEM" "SYSTEMDB" "${line}")
        cmd=$(prepare_sql_statement "$VIP" "$DB_PORT" "$SID" "${line}")
        execute_and_echo "$cmd" "$1"
    done
}

# Create the SRTAKEOVER user store key
# Create a DB user and grant necessary privileges
function srtakeover_user_hana_1(){
    # provide $1 to supress execution
    local line cmd
    echo_green "This creates a key for HANA versions prior to 2.0 SPS01 using port 3xx15."
    execute_and_echo "su -lc 'hdbuserstore set SRTAKEOVER ${VIP}:${DB_PORT} ${REPO_USER} ${DB_PASS}' $ADMUSER" "$1"
    for line in "${REPO_USER_SQL[@]}"; do
        cmd=$(prepare_sql_statement "$VIP" "$DB_PORT" "$SID" "${line}")
        execute_and_echo "$cmd" "$1"
    done
}

# Check that the SRTAKEOVER user key is present,
# there is a HANA DB user called ${REPO_USER} and
# it has all the necessary priviledges
function srtakeover_user_check(){
    local key rc stmt cmd out grp sub
    # get the key
    key=$(su -lc 'hdbuserstore list SRTAKEOVER' "$ADMUSER"); rc=$?
    if [[ $rc -eq 0 ]]; then
        echo_green "HDB User Store key SRTAKEOVER is present:"
        echo "$key"
    else
        echo_red "HDB User Store key SRTAKEOVER is NOT present"
        exit 1
    fi
    # check if the key references our user
    echo "$key" | grep "USER: ${REPO_USER}" &>/dev/null; rc=$?
    if [[ $rc -eq 0 ]]; then
        echo_green "The key references user ${REPO_USER}"
    else
        echo_red "The key does not reference user ${REPO_USER}!"
        exit 1
    fi
    # check our DB user exists
    stmt="SELECT USER_NAME FROM SYS.USERS WHERE USER_NAME='${REPO_USER}'"
    cmd=$(prepare_sql_statement localhost ${DB_PORT_SYSTEM} SYSTEMDB "$stmt" "-xCa") 
    out=$(eval "$cmd"); rc=$?
    if [[ -z "$out" ]]; then
        if [[ $rc -eq 43 ]]; then
            echo_yellow ">> Could not connect to the local HANA instance (ignore if secondary)"
            exit 0
        else
            echo_red ">> There is no DB user ${REPO_USER}"
            exit 1
        fi
    else
        echo_green "Found DB user ${REPO_USER}"
    fi
    stmt="SELECT USER_NAME,OBJECT_TYPE,SCHEMA_NAME,OBJECT_NAME,COLUMN_NAME,PRIVILEGE FROM PUBLIC.EFFECTIVE_PRIVILEGES where USER_NAME = 'MY_REPO_IMPORT_USER' and  IS_VALID = 'TRUE';"
    cmd=$(prepare_sql_statement localhost ${DB_PORT_SYSTEM} SYSTEMDB  "$stmt" "-xCa")
    out=$(eval "$cmd")
    # check DB user's privileges
    echo_yellow "Checking User Privileges:"
    for sub in "REPOSITORY_REST,?,EXECUTE" "REPO_PACKAGE_ROOT,?,REPO.READ" "SYSTEMPRIVILEGE,?,?,?,REPO.IMPORT" "_SYS_REPO,DELIVERY_UNITS,?,SELECT" ".REPO_PACKAGE_ROOT,?,REPO.ACTIVATE_IMPORTED_OBJECTS"; do
        grp=$(echo "$out" | grep "$sub"); rc=$?
        if [[ $rc -eq 0 ]]; then
            echo_green "  Found privilege: $grp"
        else
            echo_red "  Could not find privilege: $grp"
        fi
    done
}

function cluster_monitor_once(){
    execute_and_echo "crm_mon -r1" "$1"
}

function cluster_monitor_rec(){
    execute_and_echo "crm_mon -r" "$1"
}

function sys_overview(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'HDBSettings.sh systemOverview.py' '$ADMUSER'" "$1"
}

function upgrade_hana(){
    execute_and_echo "${UPD_LOCATION}/hdblcmgui --action=update --hdbupd_server_ignore=check_min_mem" "$1"
}

function hana_backup_sdc(){
    local loc_node sql_stmt
    loc_node=$(hostname -s)
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        sql_stmt="BACKUP DATA USING FILE ('initialbackup')"
        cmd=$(prepare_sql_statement_sdc "$sql_stmt")
        execute_and_echo "$cmd" "$1"
    else
        echo_red "This is not the primary node!"
        exit 1
    fi
}

function hana_backup_mdcf(){
    local loc_node sql_stmt
    loc_node=$(hostname -s)
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        sql_stmt="BACKUP DATA FOR FULL SYSTEM USING FILE ('initialbackup')"
        cmd=$(prepare_sql_statement "$VIP" "$DB_PORT_SYSTEM" "SYSTEMDB" "$sql_stmt")
        execute_and_echo "$cmd" "$1"
    else
        echo_red "This is not the primary node!"
        exit 1
    fi
}

function hana_backup_mdc(){
    local loc_node sql_stmt tenant_db_str tenant_db tenant_port cmd backup_stmt
    loc_node=$(hostname -s)
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        # according to this: https://help.sap.com/viewer/6b94445c94ae495c83a19646e7c3fd56/2.0.00/en-US/440f6efe693d4b82ade2d8b182eb1efb.html
        # SELECT DATABASE_NAME, SERVICE_NAME, PORT, SQL_PORT, (PORT + 2) HTTP_PORT FROM SYS_DATABASES.M_SERVICES WHERE DATABASE_NAME='<DBNAME>' and ((SERVICE_NAME='indexserver' and COORDINATOR_TYPE= 'MASTER') or (SERVICE_NAME='xsengine'))
        # first get all tenants
        sel_stmt="SELECT DATABASE_NAME, SQL_PORT FROM SYS_DATABASES.M_SERVICES WHERE SQL_PORT<>0"
        cmd=$(prepare_sql_statement localhost ${DB_PORT_SYSTEM} SYSTEMDB "${sel_stmt}" "-xCa")
        TENANTS=$(eval "$cmd")
        # iterate over tenants, backing them up
        for tenant_db_str in ${TENANTS}; do
            IFS=',' read -r tenant_db tenant_port <<< "$tenant_db_str"
            backup_stmt="BACKUP DATA USING FILE ('initial_${tenant_db}')"
            echo_green "Tenant $tenant_db at port $tenant_port"
            cmd=$(prepare_sql_statement "localhost" "$tenant_port" "$tenant_db" "${backup_stmt}")
            execute_and_echo "$cmd" "$1"
        done
    else
        echo_red "This is not the primary node!"
        exit 1
    fi
}

function hana_copy_keys(){
    # provide $1 to supress execution
    local key_path dat_path
    key_path="/hana/shared/${SID}/global/security/rsecssfs/key/SSFS_${SID}.KEY"
    dat_path="/hana/shared/${SID}/global/security/rsecssfs/data/SSFS_${SID}.DAT"

    local loc_node rem_node
    loc_node=$(hostname -s)
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        rem_node="$SEC_HNAME"
    else
        rem_node="$PRIM_HNAME"
    fi
    execute_and_echo "scp ${key_path} ${rem_node}:${key_path}" "$1"
    execute_and_echo "scp ${dat_path} ${rem_node}:${dat_path}" "$1"
}

function uninstall_hana(){
    # provide $1 to supress execution
    execute_and_echo "/hana/shared/${SID}/hdblcm/hdblcm --action=uninstall" "$1"
}

function hdb_console(){
    if [[ $# -lt 2 ]]; then
        echo_red -e "Wrong number of aruments.\nUsage: hdb_console <component> <command>"
        print_help
        exit 1
    fi
    local component="$1"
    local hcommand="$2"
    execute_and_echo "su -lc 'hdbcons -e $component \"$hcommand\"' $ADMUSER" "$3"
}

function hdb_landscape(){
    execute_and_echo "su -lc 'HDBSettings.sh landscapeHostConfiguration.py' $ADMUSER" "$1"
}

function __cmp_key(){
    local loc_chsum=$1
    local rem_chsum=$2
    echo "  Local:  $loc_chsum"
    echo "  Remote: $rem_chsum"
    if [[ "$loc_chsum" == "$rem_chsum" ]]; then
        echo_green ">> Sums match"
    else
        echo_red ">> Sums don't match!"
    fi
}

function md5_check_keys(){
    local key_path dat_path
    local loc_node rem_node loc_rc rem_rc

    key_path="/hana/shared/${SID}/global/security/rsecssfs/key/SSFS_${SID}.KEY"
    dat_path="/hana/shared/${SID}/global/security/rsecssfs/data/SSFS_${SID}.DAT"

    loc_node=$(hostname -s)
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        rem_node="$SEC_HNAME"
    else
        rem_node="$PRIM_HNAME"
    fi

    echo_yellow "Comparing PKI SSFS keys on $loc_node (local) and $rem_node (remote)"
    cmd="md5sum $key_path"
    loc_sum=$(eval "$cmd")
    # shellcheck disable=SC2029
    rem_sum=$(ssh $rem_node "$cmd")
    __cmp_key "$loc_sum" "$rem_sum"
    cmd="md5sum $dat_path"
    loc_sum=$(eval "$cmd")
    # shellcheck disable=SC2029
    rem_sum=$(ssh $rem_node "$cmd")
    __cmp_key "$loc_sum" "$rem_sum"
}

function kill_hana(){
    execute_and_echo "su -lc 'HDB kill-9' $ADMUSER" "$1"
}

function hdbsql(){
    execute_and_echo "su -lc \"hdbsql -j -u $DB_USER -n localhost:${DB_PORT} -p $DB_PASS \" $ADMUSER" "$1"
}

function hdbsql_sys(){
    execute_and_echo "su -lc \"hdbsql -j -d SYSTEMDB -u $DB_USER -n localhost:${DB_PORT_SYSTEM} -p $DB_PASS \" $ADMUSER" "$1"
}

VERB="$1"
shift

case "$VERB" in
     enable)
        enable_primary "$@"
        ;;
     disable)
        disable_primary "$@"
        ;;
     register)
        register_secondary "$@"
        ;;
    unregister)
        unregister_secondary "$@"
        ;;
    cleanup | c)
        sr_cleanup "$@"
        ;;
    state | s)
        sr_state "$@"
        ;;
    state-c | sc)
        sr_state_control "$@"
        ;;
    status | ss)
        sr_status "$@"
        ;;
    status-c | ssc)
        sr_status_control "$@"
        ;;
    upgrade)
        upgrade_hana "$@"
        ;;
    mon)
        cluster_maintenance on "$@"
        ;;
    moff)
        cluster_maintenance off "$@"
        ;;
    m)
        cluster_monitor_once "$@"
        ;;
    mm)
        cluster_monitor_rec "$@"
        ;;
    cup)
        resource_cleanup "$@"
        ;;
    mig)
        migrate_vip "$@"
        ;;
    fip)
        find_vip "$@"
        ;;
    start)
        hdb_command start "$@"
        ;;      
    stop)
        hdb_command stop "$@"
        ;;
    info)
        hdb_command info "$@"
        ;;
    overview | o)
        sys_overview "$@"
        ;;
    version)
        hdb_command version "$@"
        ;;
    dummy)
        select_dummy "$@"
        ;;
    ctemp)
        create_temp "$@"
        ;;
    stemp)
        select_temp "$@"
        ;;
    wtemp)
        write_temp "$@"
        ;;
    takeover)
        hana_take_over "$@"
        ;;
    backup-sdc)
        hana_backup_sdc "$@"
        ;;
    backup-mdc)
        hana_backup_mdc "$@"
        ;;
    backup-mdcf)
        hana_backup_mdcf "$@"
        ;;
    copy-keys)
        hana_copy_keys "$@"
        ;;
    su)
        su - "$ADMUSER"
        ;;
    fh)
        SAPHanaSR-showAttr
        ;;
    blockt)
        iptables -P INPUT DROP
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        # NFS
        # TODO: these are not necessarily the ports used by the nfs-client!
        iptables -A INPUT -p tcp -m tcp -m multiport --dports 111,1039,1047,1048,2049 -j ACCEPT
        iptables -A INPUT -p udp -m udp -m multiport --dports 111,1039,1047,1048,2049 -j ACCEPT
        ;;
    unblockt)
        iptables -F
        iptables -P INPUT ACCEPT
        ;;
    srtakeover2)
        srtakeover_user_hana_2_sps1 "$@"
        ;;
    srtakeover1)
        srtakeover_user_hana_1 "$@"
        ;;
    srtakeover-check | check-srtakeover)
        srtakeover_user_check "$@"
        ;;
    uninstall)
        uninstall_hana "$@"
        ;;
    console)
        hdb_console "hdbindexserver" "replication info" "$@"
        ;;
    landscape)
        hdb_landscape "$@"
        ;;
    check-keys)
        md5_check_keys "$@"
        ;;
    kill)
        kill_hana "$@"
        ;;
    hdbsql)
        hdbsql "$@"
        ;;
    hdbsql-sys)
        hdbsql_sys "$@"
        ;;
    install)
        if [[ -f /root/sap_inst/install_hana.sh ]]; then
            /root/sap_inst/install_hana.sh inst "$@"
        else
            echo_red "Could not find /root/sap_inst/install_hana.sh. Is the share mounted?"
            exit 1
        fi
        ;;
    '-h')
        print_help
        exit 0
        ;;
    *)
        echo "Unsupported command: '$VERB'"
        print_help
        exit 1
esac
