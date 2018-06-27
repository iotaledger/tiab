#!/bin/bash

DOCKER_REGISTRY=karimo/iri-network-tests

echo --------------------------
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

if [ -d docker/iri ]; then
  cd docker/iri
  git fetch --all
  git checkout origin/$REPO_BRANCH
  cd ../..
else
  git clone --depth 1 --branch $REPO_BRANCH $REPO_URL docker/iri
fi

cd docker/iri
REVISION=$(git rev-parse HEAD)
cd ..

echo --------------------------
echo "Deploying revision $REVISION"
echo --------------------------

if [ $(curl -s -w "%{http_code}" https://registry.hub.docker.com/v2/repositories/$DOCKER_REGISTRY/tags/$REVISION/ -o /dev/null) != '200' ]; then
  if [ $(docker images | grep $DOCKER_REGISTRY | grep -c $REVISION) -eq 0 ]; then
    docker build -t $DOCKER_REGISTRY:$REVISION .
  fi 
  docker push $DOCKER_REGISTRY:$REVISION 
fi

cd ..

kubectl create configmap tanglescope-$REVISION --from-file configs/tanglescope.yml
cat \
  <(kubectl get configmap tanglescope-$REVISION -o json) \
  <(echo '{ "metadata": { "labels": { "revision": "'$REVISION'" } } }') |
  jq -s '.[0] * .[1]' |
kubectl replace -f -

sed "s/NUMBER_PLACEHOLDER/$NODE_NUMBER/" <iri-tanglescope-deployment.yml |
  sed "s/IRI_IMAGE_PLACEHOLDER/${DOCKER_REGISTRY//\//\\\/}:$REVISION/" |
  sed "s/REVISION_PLACEHOLDER/$REVISION/g" |
  kubectl create -f -

IRI_TARGETS_JSON=$(mktemp)
PROMETHEUS_CONFIG_DIR=$(mktemp -d)

echo --------------------------
echo "Waiting until IRIs are healthy"
echo --------------------------

while kubectl get pods -l revision=$REVISION | tail -n+2 | grep -v Running >/dev/null; do
  sleep 5
done

kubectl get pods -l revision=$REVISION -o json | jq '{ iri_targets: [ .items[].status.podIP ] } ' >$IRI_TARGETS_JSON

j2 -f json configs/templates/prometheus.j2 $IRI_TARGETS_JSON >$PROMETHEUS_CONFIG_DIR/prometheus.yml

kubectl create configmap prometheus-$REVISION --from-file $PROMETHEUS_CONFIG_DIR/prometheus.yml
cat \
  <(kubectl get configmap prometheus-$REVISION -o json) \
  <(echo '{ "metadata": { "labels": { "revision": "'$REVISION'" } } }') |
  jq -s '.[0] * .[1]' |
kubectl replace -f -

sed "s/REVISION_PLACEHOLDER/$REVISION/g" prometheus-grafana-pod.yml |
  kubectl create -f -

sed "s/REVISION_PLACEHOLDER/$REVISION/g" prometheus-grafana-service.yml |
  kubectl create -f -

echo --------------------------
echo "Waiting until Grafana is healthy"

while kubectl get pods -l app=grafana,revision=$REVISION | tail -n+2 | grep -v Running >/dev/null; do
  sleep 5
done

LB_ENDPOINT=$(kubectl get service grafana-$REVISION -o json | jq -r '.status.loadBalancer.ingress[0].hostname')

while ! curl \
  -o /dev/null -s "http://$LB_ENDPOINT/api/datasources" --user admin:admin -H 'X-Grafana-Org-Id: 1' -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"Prometheus","isDefault":true,"type":"prometheus","url":"http://localhost:9090","access":"proxy","jsonData":{"keepCookies":[],"httpMethod":"GET"},"secureJsonFields":{}}'
do
  sleep 1
done

echo "You can now connect to http://$LB_ENDPOINT with admin:admin"
echo --------------------------
