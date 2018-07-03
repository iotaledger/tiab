#!/bin/bash

OPTS=$(getopt -o r: --long revision: -- "$@")
eval set -- $OPTS

if [ $1 = '-r' -o $1 = '--revision' ]; then
  REVISION=$2
fi

if [ -z "$REVISION" ]; then
  echo -n "Revision to nuke: "
  read REVISION
fi

kubectl delete all -l revision=$REVISION
kubectl delete cm -l revision=$REVISION
