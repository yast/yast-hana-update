#!/bin/bash
# HANA cluster debug and test script
# I. Manyugin <imanyugin@suse.com>
# Version: 1.0.3

# HANA 
SID="PRD"
INO="00"
ADMUSER="$(echo "$SID" | tr '[:upper:]' '[:lower:]')adm"
PRIM_NAME="NUREMBERG"
SEC_NAME="PRAGUE"
PRIM_HNAME="hana01"
SEC_HNAME="hana02"
HANA_RSC="msl_SAPHana_${SID}_HDB${INO}"
HANAT_RSC="cln_SAPHanaTopology_${SID}_HDB${INO}"
VIP_RSC="rsc_ip_${SID}_HDB${INO}"
VIP='192.168.101.100'
DB_USER='SYSTEM'
DB_PASS='Qwerty1234'
DB_PORT=30015
UPD_LOCATION="/hana/upd/DATA_UNITS/HDB_LCM_LINUX_X86_64/"

function print_help(){
    cat <<-EOF
Supported commands:

* HANA
  ----
  start       start HANA
  stop        stop HANA
  info        show HANA processes
  version     show HANA version
  overview    show HANA overview
  dummy       select DUMMY from the DB using the VIP
  ctemp       create table ZZZ_MYTEMP
  stemp       select from table ZZZ_MYTEMP
  wtemp       insert into table ZZZ_MYTEMP
  upgrade     upgrade HANA

* HANA system replication
  -----------------------
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
    echo -e "\e[33m\e[1m> $1\e[0m"
}

function echo_retcode(){
    echo -e "\e[33m\e[1m>> Return code: $1\e[0m"
}

function echo_green(){
    echo -e "\e[1m\e[32m$1\e[0m"
}

function echo_red(){
    echo -e "\e[1m\e[31m$1\e[0m"
}

function echo_yellow(){
    echo -e "\e[1m\e[33m$1\e[0m"
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

function prep_sql(){
    echo "su -lc 'hdbsql -j -u $DB_USER -n ${VIP}:${DB_PORT} -p $DB_PASS \"$1\"' $ADMUSER"
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
    local cmd=$(prep_sql "SELECT * FROM DUMMY")
    execute_and_echo "$cmd" "$1"
}

function select_temp(){
    # provide $1 to supress execution
    local cmd=$(prep_sql "SELECT * FROM ZZZ_MYTEMP")
    execute_and_echo "$cmd" "$1"
}

function write_temp(){
    # provide $1 to supress execution
    local val cmd
    val=$(date +'%F %T.%N')
    echo_yellow "Inserting value '$val'"
    cmd=$(prep_sql "INSERT INTO ZZZ_MYTEMP VALUES('\''WOOHOO $val'\'');")
    execute_and_echo "$cmd" "$1"
}

function create_temp(){
    # provide $1 to supress execution
    local cmd
    cmd=$(prep_sql "CREATE TABLE ZZZ_MYTEMP (fld VARCHAR(255));")
    execute_and_echo "$cmd" "$1"
}

function hana_take_over(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_takeover' $ADMUSER" "$1"
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
        upgrade_hana
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
        iptables -A INPUT -p tcp -m tcp -m multiport --dports 111,1039,1047,1048,2049 -j ACCEPT
        iptables -A INPUT -p udp -m udp -m multiport --dports 111,1039,1047,1048,2049 -j ACCEPT
        ;;
    unblockt)
        iptables -F
        iptables -P INPUT ACCEPT
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