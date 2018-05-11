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
    sleep 2

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

    if [ $instancestostart -lt 15 ]; then
	timeout=30
    else
	timeout=$(($instancestostart * 3))
    fi

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
	    nostart=$(($instancestostart+$baseinstancetostart-$count))
	    echo "\e[01;31mFAILED: $nostart instances did not come up in time \e[0m"
	    return $FAILED
	fi

    done
}

function main {
    local count=0

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
	RESULT=$?
    }

    if [ $RESULT -eq $FAILED ]; then
	return $FAILED
    else
	echo -e "\e[01;92m\nCompleted with 0 failures \e[0m"
	return 0
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
