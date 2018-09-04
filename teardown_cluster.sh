#!/bin/bash

OPTS=$(getopt -o t: --long tag: -- "$@")
eval set -- $OPTS

if [ $1 = '-t' -o $1 = '--tag' ]; then
  TAG=$2
fi

if [ -z "$TAG" ]; then
  echo -n "Revision to nuke: "
  read TAG
fi

kubectl delete all -l tag=$TAG
kubectl delete cm -l tag=$TAG
