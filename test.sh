#!/bin/bash

DOCKER_REGISTRY=karimo/iri-network-tests

echo -n "How many nodes do you want?
> "
read NODE_NUMBER

echo -n "Select scenario:
(1) Node initial sync
(2) Transaction gossiping
> "

read SCENARIO

if [ $SCENARIO != '1' -a $SCENARIO != '2' ]; then
  echo Invalid scenario.
  exit 1
fi

if [ $SCENARIO = '1' ]; then
  echo -n "How many full nodes do you want?
> "
  read FULL_NODES
  EMPTY_NODES=$(expr $NODE_NUMBER - $FULL_NODES)
  
  if [ $EMPTY_NODES -lt 1 ]; then
    echo Invalid number of nodes specified.
    exit 1
  fi
fi

echo -n "Select topology:
(1) All x All
(2) Chain
> "

read TOPOLOGY
if [ $TOPOLOGY != '1' -a $TOPOLOGY != '2' ]; then
  echo Invalid topology specified.
  exit 1
fi

echo -n "IRI Repo URL (defaults to iotaledger)
> "
read REPO_URL
if [ -z $REPO_URL ]; then REPO_URL=https://github.com/iotaledger/iri.git; fi

echo -n "Revision (defaults to dev)
> "
read REPO_BRANCH
if [ -z $REPO_BRANCH ]; then REPO_BRANCH=dev; fi

echo Thanks, building images...
echo --------------------------

rm -rf docker/iri
git clone --depth 1 --branch $REPO_BRANCH $REPO_URL docker/iri

cd docker/iri
REVISION=$(git rev-parse HEAD)
cd ..

if [ $(curl -s -w "%{http_code}" https://registry.hub.docker.com/v2/repositories/$DOCKER_REGISTRY/tags/$REVISION/ -o /dev/null) != '200' ]; then
  if [ $(docker images | grep $DOCKER_REGISTRY | grep -c $REVISION) -eq 0 ]; then
    docker build -t $DOCKER_REGISTRY:$REVISION .
  fi 
  docker push $DOCKER_REGISTRY:$REVISION 
fi
