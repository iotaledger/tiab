#!/bin/bash

DEBUG=0

if [ $DEBUG -eq 1 ]; then
  set -x
fi

DOCKER_REGISTRY=karimo/iri-network-tests
IRI_DB_URL=https://s3.eu-central-1.amazonaws.com/iotaledger-dbfiles/testnet/db-latest.tgz

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
  EMPTY_NODES=$(($NODE_NUMBER - $FULL_NODES))
  
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

echo -n "Select gossip protocol:
(1) TCP
(2) UDP
> "

read PROTOCOL
if [ $PROTOCOL != '1' -a $PROTOCOL != '2' ]; then
  echo Invalid protocol specified.
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

function add_node_neighbor {
  local NODE_API=$1
  local NEIGHBOR_IP=$2

  if [ $PROTOCOL = 1 ]; then
    local SCHEME='tcp://'
  else
    local SCHEME='udp://'
  fi

  curl -s -o /dev/null http://$NODE_API:14265 \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'X-IOTA-API-Version: 1' \
    -d '{"command": "addNeighbors", "uris": ["'${SCHEME}${NEIGHBOR_IP}':14700"]}'
}

function add_node_mutual_neighbor {
  add_node_neighbor $1 $4
  add_node_neighbor $3 $2
}

function chain_topology {
  declare -a _IRI_APIS=("${!1}")
  declare -a _IRI_IPS=("${!2}")
  for i in $(seq 0 $((${#_IRI_IPS[@]} - 2))); do
      add_node_mutual_neighbor ${_IRI_APIS[$i]} ${_IRI_IPS[$i]} ${_IRI_APIS[$(($i + 1))]} ${_IRI_IPS[$(($i + 1))]}
  done
}

function all_to_all_topology {
  declare -a _IRI_APIS=("${!1}")
  declare -a _IRI_IPS=("${!2}")
  for i in $(seq 0 $((${#_IRI_IPS[@]} - 1))); do
    for x in $(seq $((i + 1)) $((${#_IRI_IPS[@]} - 1))); do
      add_node_mutual_neighbor ${_IRI_APIS[$i]} ${_IRI_IPS[$i]} ${_IRI_APIS[$x]} ${_IRI_IPS[$x]}
    done
  done
}

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

if [ $SCENARIO = '2' ]; then
  FULL_NODES=$NODE_NUMBER
  EMPTY_NODES=0
fi

for node_num in $(seq 1 $NODE_NUMBER); do
  if [ $node_num -le $FULL_NODES ]; then
    sed "s/NODE_NUMBER_PLACEHOLDER/$node_num/" <iri-tanglescope.yml |
      sed "s#IRI_IMAGE_PLACEHOLDER#$DOCKER_REGISTRY:$REVISION#" |
      sed "s/REVISION_PLACEHOLDER/$REVISION/g" |
      sed 's/ISFULL_PLACEHOLDER/"true"/g' |
      sed "s#IRI_DB_URL_PLACEHOLDER#$IRI_DB_URL#g" |
      kubectl create -f -
  else
    sed "s/NODE_NUMBER_PLACEHOLDER/$node_num/" <iri-tanglescope.yml |
      sed "s#IRI_IMAGE_PLACEHOLDER#$DOCKER_REGISTRY:$REVISION#" |
      sed "s/REVISION_PLACEHOLDER/$REVISION/g" |
      sed 's/ISFULL_PLACEHOLDER/"false"/g' |
      sed 's#IRI_DB_URL_PLACEHOLDER#""#g' |
      kubectl create -f -
  fi
done

IRI_TARGETS_JSON_FILE=$(mktemp)
PROMETHEUS_CONFIG_DIR=$(mktemp -d)

echo --------------------------
echo "Waiting until IRIs are healthy"
echo --------------------------

while kubectl get pods -l revision=$REVISION | tail -n+2 | grep -v Running >/dev/null; do
  sleep 5
done

kubectl get pods -l revision=$REVISION -o json | jq '{ iri_targets: [ .items[].status.podIP ] } ' >$IRI_TARGETS_JSON_FILE

j2 -f json configs/templates/prometheus.j2 $IRI_TARGETS_JSON_FILE >$PROMETHEUS_CONFIG_DIR/prometheus.yml

kubectl create configmap prometheus-$REVISION --from-file $PROMETHEUS_CONFIG_DIR/prometheus.yml
cat \
  <(kubectl get configmap prometheus-$REVISION -o json) \
  <(echo '{ "metadata": { "labels": { "revision": "'$REVISION'" } } }') |
  jq -s '.[0] * .[1]' |
kubectl replace -f -

sed "s/REVISION_PLACEHOLDER/$REVISION/g" prometheus-grafana.yml |
  kubectl create -f -

echo --------------------------
echo "Waiting until Grafana is healthy"

while kubectl get pods -l app=grafana,revision=$REVISION | tail -n+2 | grep -v Running >/dev/null; do
  sleep 5
done

LB_ENDPOINT=$(kubectl get service grafana-$REVISION -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
while [ $LB_ENDPOINT = 'null' -o -z $LB_ENDPOINT]; do
  LB_ENDPOINT=$(kubectl get service grafana-$REVISION -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
done

while ! curl -s -o /dev/null "http://$LB_ENDPOINT/api/datasources" \
  --user admin:admin -H 'X-Grafana-Org-Id: 1' -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"Prometheus","isDefault":true,"type":"prometheus","url":"http://localhost:9090","access":"proxy","jsonData":{"keepCookies":[],"httpMethod":"GET"},"secureJsonFields":{}}'
do
  sleep 1
done

IFS=' ' read -a IRI_APIS <<<$(kubectl get service -l app=iri,revision=$REVISION -o json | jq -r '[ .items[].status.loadBalancer.ingress[0].hostname ] | join(" ")')

echo "You can now connect to Grafana at http://$LB_ENDPOINT with admin:admin"
echo "IRI API Endpoints:"
for i in "${!IRI_APIS[@]}"; do
  echo -e "\t - http://${IRI_APIS[$i]}:14265"
done
echo "Configuring nodes topology..."

IFS=' ' read -a IRI_IPS <<<$(jq -r '.iri_targets | join(" ")' <$IRI_TARGETS_JSON_FILE)

if [ $TOPOLOGY -eq 1 ]; then
  all_to_all_topology IRI_APIS[@] IRI_IPS[@]
else
  chain_topology IRI_APIS[@] IRI_IPS[@]
fi

echo "All done bro!"
echo --------------------------
