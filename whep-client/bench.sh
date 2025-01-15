#!/bin/bash

USAGE="
Usage: $(basename "$0") [options] whep-server-url

where:
    -h show this help text
    -n number of sessions

Example: $(basename "$0") -n 10 http://localhost:4000
"

SESSIONS=1

while getopts ":hc:n:" opt; do
    case $opt in
    h)
        echo "$USAGE"
        exit
        ;;
    n)
        SESSIONS="$OPTARG"
        ;;
    :) 
        echo "missing argument for -$OPTARG"
        exit
    esac
done

shift $((OPTIND -1))

if [ $# -ne 1 ]
then
    echo "Bad number of positional arguments. Expected: 1, got: $# $*."
    echo "$USAGE"
    exit 1
fi

URL=$1

# Use () i.e. subshell to spawn everything within it and trap ctrl+c 
# to shutdown all tasks, see https://stackoverflow.com/a/52033580/9620900
(
trap 'kill 0' SIGINT; 
for ((i=0; i < $SESSIONS; i++)); do
    echo "Starting session $i"
    whep-client $URL &
    sleep 0.05
done
wait $(jobs -p)
)