#!/bin/bash

echo -n "Revision to nuke: "
read REVISION
kubectl delete all -l revision=$REVISION
kubectl delete cm -l revision=$REVISION
