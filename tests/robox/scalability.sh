#!/bin/bash

# Use `<scriptname> -n <num_instances>` to run

ROBOX=$PWD/robox
ROBOXLOGDIR=/tmp/robox
ROBOXFAILLOG=$ROBOXLOGDIR/robox-faillog
SCALABILITYFAILLOG=$ROBOXLOGDIR/scalability-faillog
INSTANCEUPMSGFREQ=10

maxinstances=254
instancestostart=1    # Start 1 instance by default
baseinstancetostart=0 # Start from 1 by default

FAILED=255
QUIET="-q"

function stop_instances {
    local result
    local instance
    local dockerdangle

    if [ "$FORCESTOPALL" == "" ]; then
	echo "Scanning for instances to stop"
    else
	echo -n "Forcibly stopping instances $((1+$baseinstancetostart)) "
	echo    "through $(($instancestostart+$baseinstancetostart))"
    fi

    for ((i=1; i<=$instancestostart; i++)); do
	instance=$(($i+$baseinstancetostart))
	if [ "$FORCESTOPALL" == "" ]; then
	    result=$(ps aux | grep "instance$i" | grep -v grep)
	    if [ "$result" != "" ]; then
		echo "Stopping instance $instance"
		$ROBOX stop $instance -f $QUIET &
	    fi
	else
	    $ROBOX stop $instance -f $QUIET &
	fi
    done

    echo "Waiting for all instances to stop ..."
    wait

    dockerdangle=`docker ps -aq --no-trunc -f status=exited`
    if [ "$dockerdangle" != "" ]; then
	echo "Removing any dangling/exited Docker instances"
	docker ps -aq --no-trunc -f status=exited | xargs docker rm
	sleep .2
    fi
}

function start_instances {
    echo "Starting $instancestostart instances (base: $baseinstancetostart)"
    for ((i=1; i<=instancestostart; i++)); do
	instance=$(($i+$baseinstancetostart))
	$ROBOX start $instance $QUIET &
    done
}

function count_instances {
    local count=0
    local last=$count
    local sleeptime=5
    local iterations=0
    local timeout=0
    local lines=0

    if [ $instancestostart -lt 15 ]; then
	timeout=30
    else
	timeout=$(($instancestostart * 2))
    fi

    count=0
    while [ $count -lt $(($instancestostart+$baseinstancetostart)) ]; do
	count=$(ps aux | grep "x11vnc" | grep -v grep | wc -l)

	sleep $sleeptime

	if [ $(($count-$INSTANCEUPMSGFREQ)) -ge $last -o $count -eq $instancestostart ]; then
	    echo "$count instances now up"
	    last=$count
	fi

	iterations=$(($iterations+1))
	if [ $(($iterations*$sleeptime)) -gt $timeout ]; then
	    count=$(ps aux | grep "x11vnc" | grep -v grep | wc -l)
	    lines=$(wc -l $ROBOXFAILLOG | cut -d' ' -f1)
	    insert=$(($instancestostart+$baseinstancetostart-($count+$lines)))
	    for ((i=0; i<$insert; i++)); do
		echo "DUMMY" >> $ROBOXFAILLOG
	    done
	    echo "FAILED: One or more instances did not come up in time"
	    return $FAILED
	fi

	# Also include the broken instances for the break
	lines=$(wc -l $ROBOXFAILLOG | cut -d' ' -f1)
	count=$(($count+$lines))
    done
}

function reboot {
    instance=$1

    echo "Trying to re-start failed instance $instance"
    $ROBOX stop $instance -f -v $QUIET
    $ROBOX start $instance $QUIET
}

function retry {
    # Try to restart failed instance one more time
    #
    # BUG: https://github.com/google/protobuf/issues/3991

    lines=$(wc -l $ROBOXFAILLOG | cut -d' ' -f1)
    if [ $lines -gt 0 ]; then
	echo -e "\e[01;31mThere were start-up failures - trying to restart $lines instances \e[0m"
    else
	return
    fi

    cp $ROBOXFAILLOG $SCALABILITYFAILLOG
    rm $ROBOXFAILLOG 2>&1 > /dev/null
    touch $ROBOXFAILLOG

    for instance in `cat $SCALABILITYFAILLOG`; do
	if [[ "$instance" != "DUMMY" ]]; then
	    reboot $instance &
	fi
    done

    count_instances
}

function main {
    local count=0

    mkdir -p $ROBOXLOGDIR
    rm -f $ROBOXFAILLOG
    touch $ROBOXFAILLOG

    if [ "$DONTSTOP" == "" ]; then
	stop_instances
	if [ $? -eq $FAILED ]; then
	    return $FAILED
	fi
    fi

    if [ "$ONLYSTOP" == "true" ]; then
	return
    fi

    if [ $baseinstancetostart -eq 0 ]; then
	count=$(ps aux | grep "session-manager" | grep -v grep | wc -l)
	if [ $count -gt 0 ]; then
	   ps aux | grep "session-manager" | grep -v grep | wc -l
	   echo "Other instances are still running and no base (-b) was specified"
	   echo "Either close all instances or provide a base to start from - exiting"
	   return $FAILED
	fi
    fi

    time {
	start_instances
	count_instances
	retry
    }

    lines=$(wc -l $ROBOXFAILLOG | cut -d' ' -f1)
    if [ $lines -gt 0 ]; then
	echo -e "\e[01;31m\nCompleted with $lines failures \e[0m"
    else
	echo -e "\e[01;92m\nCompleted with $lines failures \e[0m"
    fi
}

if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root"
    exit 1
fi

# Ensure we have current sudoers rights
sudo ls > /dev/null

while [ $# -gt 0 ]; do
    case $1 in
	-f|--force-stop)
	    FORCESTOPALL=true
	    ;;
	-n|--number)
	    instancestostart=$2
	    shift
	    ;;
	-b|--base)
	    baseinstancetostart=$2
	    shift
	    ;;
	-v|--verbose)
	    QUIET=""
	    ;;
	-d|--debug)
	    QUIET="-d"
	    INSTANCEUPMSGFREQ=1
	    ;;
	-ds|--dont-stop)
	    DONTSTOP=true
	    ;;
	-os|--only-stop)
	    ONLYSTOP=true
	    ;;
	-r|--retry)
	    retry
	    exit 0
	    ;;
	*)
	    echo "Unrecognised parameter $1"
	    exit 1
	    ;;
    esac
    shift
done

main
