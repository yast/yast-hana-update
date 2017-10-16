#!/bin/bash
# HANA cluster debug and test script
# I. Manyugin <imanyugin@suse.com>
# Version: 1.0.3


##### CONFIGURATION
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
###### END CONFIGURATION

function print_help(){
    cat <<-EOF
YAST2-HANA-UPDATE TESTER

This script has to be run on the SECONDARY node

Supported commands:

- phase1    checks:
             - resources are in maintenance mode
             - HANA is running
             - SR is disabled for local instance

- phase2    checks:
             - HANA is running
             - SR is enabled
             - local site is primary site
             - vIP is running on local node
             - SR on node $PRIM_NAME is disabled

- phase3    checks whether cluster is in ORIGINAL state
            checks:
             - ???

- phrase3n  checks whether cluster is healthy, 
                but SECONDARY is the NEW PRIMARY
            checks:
             - ???
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

# Yes should be green
function echo_yes_no1(){
    if [[ $1 -eq 0 ]]; then
        echo_green ' Yes'
    else
        echo_red ' No'
    fi
}

# Yes should be red
function echo_yes_no2(){
    if [[ $1 -eq 0 ]]; then
        echo_red ' Yes'
    else
        echo_green ' No'
    fi
}

function yes_no_cmp(){
    local real_value=$1
    local expected=$2
    if [[ "$real_value" == "$expected" ]]; then
        echo_green ' Yes'
    else
        echo_red ' No'
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

function get_maintenance_status(){
    out=$(crm_resource --resource $1 -m -g maintenance 2>/dev/null)
    if [[ $out = "true" ]]; then
        return 0
    else
        return 1
    fi
}


function test_phase1(){
    echo_green "Test phase 1"

    if [[ $(hostname -s) != $SEC_HNAME ]]; then
        echo_red "Error: This phase has to be run on the secondary node $SEC_HNAME"
        exit 1
    fi
    
    echo_yellow "Checking resource maintenance"
    for rsc_id in $HANA_RSC $HANAT_RSC $VIP_RSC; do
        echo -n "Resource $rsc_id in maintenance mode?"
        get_maintenance_status $rsc_id; rc=$?
        if [[ $rc -eq 0 ]]; then
            echo_green ' Yes'
        else
            echo_red ' No'
        fi
    done

    echo_yellow "Local HANA"
    echo -n "process hdb.sap${SID}_HDB${INO} running"
    ps aux | grep "[h]db.sap${SID}_HDB${INO}" >/dev/null; rc=$?
    echo_yes_no1 $rc
    echo '> sr_state'
    out=$(su -lc 'hdbnsutil -sr_state --sapcontrol=1' $ADMUSER)
    echo $out | grep 'online=true' &>/dev/null; rc=$?
    echo -n " - online=true    "
    echo_yes_no1 $rc
    echo $out | grep 'mode=none' &>/dev/null; rc=$?
    echo -n " - mode=none      "
    echo_yes_no1 $rc
    echo "> systemReplicationStatus.py"
    out=$(su -lc 'HDBSettings.sh systemReplicationStatus.py --sapcontrol=1' $ADMUSER)
    echo $out | grep 'local_site_id=0' &>/dev/null; rc=$?
    echo -n " - local_site_id=0 (no SR)"
    echo_yes_no1 $rc


    echo_yellow "Remote HANA"
    echo -n "process hdb.sap${SID}_HDB${INO} running"
    ssh root@$PRIM_HNAME "ps aux" | grep "[h]db.sap${SID}_HDB${INO}" >/dev/null; rc=$?
    echo_yes_no1 $rc
    echo "> sr_state"
    out=$(ssh root@$PRIM_HNAME "su -lc 'hdbnsutil -sr_state --sapcontrol=1'" $ADMUSER)
    echo $out | grep 'online=true' &>/dev/null; rc=$?
    echo -n " - online=true    "
    echo_yes_no1 $rc
    echo $out | grep 'mode=primary' &>/dev/null; rc=$?
    echo -n " - mode=primary   "
    echo_yes_no1 $rc
    echo "> systemReplicationStatus.py"
    out=$(ssh root@$PRIM_HNAME "su -lc 'HDBSettings.sh systemReplicationStatus.py --sapcontrol=1'" $ADMUSER)
    rc=$?
    echo -n " - rc=10 (primary with no consumers)"
    yes_no_cmp $rc 10
    echo $out | grep 'site/1/REPLICATION_MODE=PRIMARY' &>/dev/null; rc=$?
    echo -n " - site/1/REPLICATION_MODE=PRIMARY  "
    echo_yes_no1 $rc

    echo_yellow "Virtual IP"
    ssh root@$PRIM_HNAME "crm_resource --resource $VIP_RSC --force-check &>/dev/null"; rc=$?
    echo -n "vIP resource $VIP_RSC running on remote node $PRIM_HNAME?"
    echo_yes_no1 $rc

    echo_yellow "Local NFS mounts:"
    grep nfs < /proc/mounts | awk '{ printf "- %s => %s\n", $1, $2 }'

}


function test_phase2(){
    echo_green "Test phase 2"

    if [[ $(hostname -s) != $SEC_HNAME ]]; then
        echo_red "Error: This phase has to be run on the secondary node $SEC_HNAME"
        exit 1
    fi

    echo_yellow "Checking resource maintenance"
    for rsc_id in $HANA_RSC $HANAT_RSC $VIP_RSC; do
        echo -n "Resource $rsc_id in maintenance mode?"
        get_maintenance_status $rsc_id; rc=$?
        if [[ $rc -eq 0 ]]; then
            echo_green ' Yes'
        else
            echo_red ' No'
        fi
    done

    echo_yellow "Local HANA"
    echo -n "checking for process hdb.sap${SID}_HDB${INO}"
    ps aux | grep "[h]db.sap${SID}_HDB${INO}" >/dev/null; rc=$?
    echo_yes_no1 $rc
    echo '> sr_state'
    out=$(su -lc 'hdbnsutil -sr_state --sapcontrol=1' $ADMUSER)
    echo $out | grep 'mode=primary' &>/dev/null; rc=$?
    echo -n " - mode=primary   "
    echo_yes_no1 $rc
    echo $out | grep 'hasConsumers=false' &>/dev/null; rc=$?
    echo -n " - hasConsumers=false"
    echo_yes_no1 $rc

    echo_yellow "Virtual IP"
    crm_resource --resource $VIP_RSC --force-check &>/dev/null; rc=$?
    echo -n "is vIP resource $VIP_RSC running locally on node $SEC_HNAME?"
    echo_yes_no1 $rc

    echo_yellow "Remote HANA"
    echo -n "checking for process hdb.sap${SID}_HDB${INO}"
    ssh root@$PRIM_HNAME "ps aux" | grep "[h]db.sap${SID}_HDB${INO}" >/dev/null; rc=$?
    echo_yes_no1 $rc
    echo "> sr_state"
    out=$(ssh root@$PRIM_HNAME "su -lc 'hdbnsutil -sr_state --sapcontrol=1'" $ADMUSER)
    echo $out | grep 'mode=primary' &>/dev/null; rc=$?
    echo -n " - mode=primary"
    echo_yes_no1 $rc

    echo_yellow "Local NFS mounts:"
    grep nfs < /proc/mounts | awk '{ printf "- %s => %s\n", $1, $2 }'

    echo_yellow "Remote NFS mounts ($PRIM_HNAME):"
    ssh root@$PRIM_HNAME "grep nfs < /proc/mounts" | awk '{ printf "- %s => %s\n", $1, $2 }'

}


function test_phase3_orig(){
    echo_green "Test phase 3 (ORIGINAL)"
    if [[ $(hostname -s) != $SEC_HNAME ]]; then
        echo_red "Error: This phase has to be run on the secondary node $SEC_HNAME"
        exit 1
    fi

    echo_yellow "Checking resource maintenance"
    for rsc_id in $HANA_RSC $HANAT_RSC $VIP_RSC; do
        echo -n "Resource $rsc_id in maintenance mode?"
        get_maintenance_status $rsc_id; rc=$?
        if [[ $rc -ne 0 ]]; then
            echo_green ' Yes'
        else
            echo_red ' No'
        fi
    done

    echo_yellow "Local HANA"
    echo -n "process hdb.sap${SID}_HDB${INO} running"
    ps aux | grep "[h]db.sap${SID}_HDB${INO}" >/dev/null; rc=$?
    echo_yes_no1 $rc
    echo '> sr_state'
    out=$(su -lc 'hdbnsutil -sr_state --sapcontrol=1' $ADMUSER)
    echo $out | grep 'online=true' &>/dev/null; rc=$?
    echo -n " - online=true    "
    echo_yes_no1 $rc
    echo $out | grep 'mode=sync' &>/dev/null; rc=$?
    echo -n " - mode=sync      "
    echo_yes_no1 $rc
    echo "> systemReplicationStatus.py"
    out=$(su -lc 'HDBSettings.sh systemReplicationStatus.py --sapcontrol=1' $ADMUSER)
    echo $out | grep 'local_site_id=2' &>/dev/null; rc=$?
    echo -n " - local_site_id=2"
    echo_yes_no1 $rc


    echo_yellow "Remote HANA"
    echo -n "process hdb.sap${SID}_HDB${INO} running"
    ssh root@$PRIM_HNAME "ps aux" | grep "[h]db.sap${SID}_HDB${INO}" >/dev/null; rc=$?
    echo_yes_no1 $rc
    echo "> sr_state"
    out=$(ssh root@$PRIM_HNAME "su -lc 'hdbnsutil -sr_state --sapcontrol=1'" $ADMUSER)
    echo $out | grep 'online=true' &>/dev/null; rc=$?
    echo -n " - online=true    "
    echo_yes_no1 $rc
    echo $out | grep 'mode=primary' &>/dev/null; rc=$?
    echo -n " - mode=primary   "
    echo_yes_no1 $rc
    echo "> systemReplicationStatus.py"
    out=$(ssh root@$PRIM_HNAME "su -lc 'HDBSettings.sh systemReplicationStatus.py --sapcontrol=1'" $ADMUSER)
    rc=$?
    echo -n " - rc=15 (SR Active)"
    yes_no_cmp $rc 15
    echo $out | grep 'site/1/REPLICATION_MODE=PRIMARY' &>/dev/null; rc=$?
    echo -n " - site/1/REPLICATION_MODE=PRIMARY  "
    echo_yes_no1 $rc

    echo_yellow "Virtual IP"
    ssh root@$PRIM_HNAME "crm_resource --resource $VIP_RSC --force-check &>/dev/null"; rc=$?
    echo -n "vIP resource $VIP_RSC running on remote node $PRIM_HNAME?"
    echo_yes_no1 $rc

    echo_yellow "Local NFS mounts:"
    grep nfs < /proc/mounts | awk '{ printf "- %s => %s\n", $1, $2 }'

    echo_yellow "Remote NFS mounts ($PRIM_HNAME):"
    ssh root@$PRIM_HNAME "grep nfs < /proc/mounts" | awk '{ printf "- %s => %s\n", $1, $2 }'
}

function test_phase3_non_orig(){
    echo_green "Test phase 3 (NO REVERT)"
    if [[ $(hostname -s) != $SEC_HNAME ]]; then
        echo_red "Error: This phase has to be run on the secondary node $SEC_HNAME"
        exit 1
    fi
    echo_red "Not implemented yet"
    exit 1
}

function prep_sql(){
    echo "su -lc 'hdbsql -j -u $DB_USER -n ${VIP}:${DB_PORT} -p $DB_PASS \"$1\"' '$ADMUSER'"
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
    execute_and_echo "su -lc 'hdbnsutil -sr_enable --name=${loc_site}' '$ADMUSER'" "$1"
}

function disable_primary(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_disable' '$ADMUSER'" "$1"
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
    execute_and_echo "su -lc 'hdbnsutil -sr_register --remoteHost=${rem_node} --remoteInstance=${INO} --replicationMode=sync --operationMode=delta_datashipping --name=${loc_site}' '$ADMUSER'" "$1"
}

function unregister_secondary(){
    # provide $1 to supress execution
    local loc_node
    loc_node=$(hostname -s)
    local rem_site
    if [[ $loc_node == "$PRIM_HNAME" ]]; then
        rem_site=$SEC_NAME
    else
        rem_site=$PRIM_NAME
    fi
    execute_and_echo "su -lc 'hdbnsutil -sr_unregister --name=$rem_site' '$ADMUSER'" "$1"
}

function sr_state(){
    # $1 = control to execute with sapcontrol
    # provide $1 to supress execution
    execute_and_echo "su -lc 'hdbnsutil -sr_state' '$ADMUSER'" "$1"
}

function sr_status(){
    # provide $1 to supress execution
    execute_and_echo "su -lc 'HDBSettings.sh systemReplicationStatus.py' '$ADMUSER'" "$1"
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
    execute_and_echo "su -lc 'HDB $func' '$ADMUSER'" "$2"
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
    execute_and_echo "su -lc 'hdbnsutil -sr_takeover' '$ADMUSER'" "$1"
}

function cluster_monitor_once(){
    execute_and_echo "crm_mon -r1" "$1"
}

function cluster_monitor_rec(){
    execute_and_echo "crm_mon -r" "$1"
}

VERB="$1"
shift

case "$VERB" in
    phase1 | 1)
        test_phase1
        ;;
    phase2 | 2)
        test_phase2
        ;;
    phase3 | 3)
        test_phase3_orig
        ;;
    phase3n | 3n)
        test_phase3_non_orig
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