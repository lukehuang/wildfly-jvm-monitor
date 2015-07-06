#!/bin/bash

FPID="/opt/jvm-monitor/pids"
HOST=$(hostname)
TIMESTAMP=0

JPPID=""
JHPID=""
JSPID1=""
JSPID2=""
FIRST=true
JHSTAT=()
JPSTAT=()
JSTAT1=()
JSTAT2=()
SENDING_DATA=""
JHRUN=1
JPRUN=1
JS1RUN=1
JS2RUN=1
LOG="/tmp/jvm-monitor.log"
ZABBIX_AGENTD_CONF="/etc/zabbix/zabbix_agentd.conf"

function getPids {
  JPPID=$(<$FPID/process-controller.pid)
  JHPID=$(<$FPID/host-controller.pid)
  JSPID1=$(<$FPID/slave-100.pid)
  JSPID2=$(<$FPID/slave-200.pid)
}

function getJstat {
  if [ -n "$1" ]; then
    TIMESTAMP=$(date +%s)
    if [[ $platform == 'sunos' ]]; then
      /opt/local/bin/sudo /opt/local/java/openjdk7/bin/jstat -gc -t $1
    else
      sudo -H -u wildfly bash -c "/usr/local/bin/jstat -gccapacity -t $1"
    fi
  fi
}

function emptyJstatArray {
  echo "0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0"
}

function checkStats {
  if [[ ${#JHSTAT[@]} < '16' ]] ; then JHSTAT=($(emptyJstatArray)); JHRUN=0 ; fi
  if [[ ${#JPSTAT[@]} < '16' ]] ; then JPSTAT=($(emptyJstatArray)); JPRUN=0 ; fi
  if [[ ${#JSTAT1[@]} < '16' ]] ; then JSTAT1=($(emptyJstatArray)); JS1RUN=0 ; fi
  if [[ ${#JSTAT2[@]} < '16' ]] ; then JSTAT2=($(emptyJstatArray)); JS2RUN=0 ; fi
}

function getHostData {
  TIMESTAMP=$(date +%s)
  SENDING_DATA="\"$HOST\" jvm.hostcontroller.NGCMX $TIMESTAMP ${JHSTAT[2]}
\"$HOST\" jvm.hostcontroller.OGCMX $TIMESTAMP ${JHSTAT[8]}
\"$HOST\" jvm.hostcontroller.PGCMX $TIMESTAMP ${JHSTAT[12]}
\"$HOST\" jvm.hostcontroller.running $TIMESTAMP $JHRUN"
}

function getProcessData {
  TIMESTAMP=$(date +%s)
  SENDING_DATA="\"$HOST\" jvm.processcontroller.NGCMX $TIMESTAMP ${JPSTAT[2]}
\"$HOST\" jvm.processcontroller.OGCMX $TIMESTAMP ${JPSTAT[8]}
\"$HOST\" jvm.processcontroller.PGCMX $TIMESTAMP ${JPSTAT[12]}"
}

function getSlave100Data {
  TIMESTAMP=$(date +%s)
  SENDING_DATA="\"$HOST\" jvm.slave100.NGCMX $TIMESTAMP ${JSTAT1[2]}
\"$HOST\" jvm.slave100.OGCMX $TIMESTAMP ${JSTAT1[8]}
\"$HOST\" jvm.slave100.PGCMX $TIMESTAMP ${JSTAT1[12]}
\"$HOST\" jvm.slave100.running $TIMESTAMP $JS1RUN"
}

function getSlave200Data {
  TIMESTAMP=$(date +%s)
  SENDING_DATA="\"$HOST\" jvm.slave200.NGCMX $TIMESTAMP ${JSTAT2[2]}
\"$HOST\" jvm.slave200.OGCMX $TIMESTAMP ${JSTAT2[8]}
\"$HOST\" jvm.slave200.PGCMX $TIMESTAMP ${JSTAT2[12]}
\"$HOST\" jvm.slave200.running $TIMESTAMP $JS2RUN"
}

function sendStats {
  if [[ $platform == 'sunos' ]] ; then
    PREFIX='/opt/local/bin/'
  else
    PREFIX=""
  fi
  # zabbix_sender $ZS_PARAM -z service.theluckycatcasino.com -s "$(hostname)" -k "cluster.status" -o "$CLUSTER_STATUS" >> $TEMP_LOG_FILE
  getProcessData
#  echo "$SENDING_DATA"
  result=$(echo "$SENDING_DATA" | ${PREFIX}zabbix_sender -c $ZABBIX_AGENTD_CONF -v -T -i - 2>&1)
#  echo "$SENDING_DATA" >> $LOG
#  echo "Result: $result" >> $LOG
  getHostData
#  echo "$SENDING_DATA"
  result=$(echo "$SENDING_DATA" | ${PREFIX}zabbix_sender -c $ZABBIX_AGENTD_CONF -v -T -i - 2>&1)
  getSlave100Data
#  echo "$SENDING_DATA"
  result=$(echo "$SENDING_DATA" | ${PREFIX}zabbix_sender -c $ZABBIX_AGENTD_CONF -v -T -i - 2>&1)
  getSlave200Data
#  echo "$SENDING_DATA"
  result=$(echo "$SENDING_DATA" | ${PREFIX}zabbix_sender -c $ZABBIX_AGENTD_CONF -v -T -i - 2>&1)
}

function getStats {
  #sudo -H -u wildfly bash -c '/usr/local/bin/jstat -gc -t 20674' && sudo -H -u wildfly bash -c '/usr/local/bin/jstat -gcutil -t 20674' && sudo -H -u wildfly bash -c "/usr/local/bin/jmap -heap 20674"
  # Timestamp        S0C    S1C    S0U    S1U      EC       EU        OC         OU       PC     PU    YGC     YGCT    FGC    FGCT     GCT
  #       107737.6 8704.0 8704.0 2751.9  0.0   70208.0  32418.3   174784.0   29565.4   36288.0 36022.9      6    0.186   2      0.222    0.408
  JHSTAT=($(getJstat $JHPID | grep -v "Timestamp"))
  JPSTAT=($(getJstat $JPPID | grep -v "Timestamp"))
  if [[ -n "$JSPID1" ]] ; then
    JSTAT1=($(getJstat $JSPID1 | grep -v "Timestamp"))
    JSTAT2=($(getJstat $JSPID2 | grep -v "Timestamp"))
  fi
  checkStats
  sendStats
}

function checkRunning {
  if [[ -n "$JHPID" ]] ; then
    if ps -p $JHPID  > /dev/null 2>&1
    then 
      getStats
    else
     if [ "$FIRST" = true ]
     then
        FIRST=false
        /opt/jvm-monitor/./create-pid-files.sh
        getPids
        checkRunning
      else
        exit 1
      fi
    fi
  fi
}

. /opt/jvm-monitor/./get-platform.sh
if [[ $platform == 'sunos' ]] ; then
  ZABBIX_AGENTD_CONF="/opt/local/etc/zabbix_agentd.conf"
fi
if [[ -n "$1" ]] ; then
  ZABBIX_AGENTD_CONF=$1
fi
getPids
checkRunning
echo $JPRUN
