#!/bin/bash

DEBUG=0
MACHINE_OUTPUT=0
SCENARIO=
NODE_NUMBER=
FULL_NODES=
TOPOLOGY=
PROTOCOL=
REPO_URL=https://github.com/iotaledger/iri.git
REPO_BRANCH=dev
DOCKER_REGISTRY=karimo/iri-network-tests
IRI_DB_URL=https://s3.eu-central-1.amazonaws.com/iotaledger-dbfiles/dev/testnet_files.tgz
API_PORT=14265
GOSSIP_TCP_PORT=14700
GOSSIP_UDP_PORT=14700

function usage {
  echo "Usage: $(basename $0) -n [node number] -s [scenario id] [-f full nodes number] -t [topology id] -p [protocol id] [-r iri repository] [-b iri branch] [-d --debug] [-m --machine-output]"
}

function print_message {
  if [ $MACHINE_OUTPUT = 0 ]; then
    echo $@
  fi
}

function check_opts {
  if [ -z $SCENARIO    ] || \
     [ -z $NODE_NUMBER ] || \
     [ -z $FULL_NODES  ] || \
     [ -z $TOPOLOGY    ] || \
     [ -z $PROTOCOL    ]; then
    usage
    exit 1
  fi

  if [ $SCENARIO = '1' ]; then
    if [ -z $FULL_NODES ]; then
      usage
      exit 1
    fi
    EMPTY_NODES=$(($NODE_NUMBER - $FULL_NODES))
    if [ $EMPTY_NODES -lt 1 ]; then
      echo ERROR: Invalid number of nodes specified. >&2
      exit 1
    fi
  fi

  if [ $SCENARIO != '1' -a $SCENARIO != '2' ]; then
    echo ERROR: Invalid scenario. >&2
    exit 1
  fi

  if [ $TOPOLOGY != '1' -a $TOPOLOGY != '2' ]; then
    echo ERROR: Invalid topology specified. >&2
    exit 1
  fi

  if [ $PROTOCOL != '1' -a $PROTOCOL != '2' ]; then
    echo ERROR: Invalid protocol specified. >&2
    exit 1
  fi
}

function add_node_neighbor {
  local NODE_API=$1
  local NEIGHBOR_IP=$2

  if [ $PROTOCOL = 1 ]; then
    local SCHEME='tcp://'
  else
    local SCHEME='udp://'
  fi

  curl -s -o /dev/null http://$NODE_API:$API_PORT \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'X-IOTA-API-Version: 1' \
    -d '{"command": "addNeighbors", "uris": ["'${SCHEME}${NEIGHBOR_IP}':$GOSSIP_TCP_PORT"]}'
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

function wait_until_iri_api_healthy {
  local NODE_API=$1
  while ! curl -s -o /dev/null http://$NODE_API:$API_PORT \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'X-IOTA-API-Version: 1' \
    -d '{"command": "getNodeInfo"}'; do
    sleep 5
  done
}

OPTS=$(getopt -o n:s:f:t:p:r:b:dma:g:u: --long number:,scenario:,fullnodes-number:,topology:,protocol:,repository:,branch:,debug,machine-output,api-port:,gossip-tcp:,gossip-udp: -- "$@")

if [ $? -ne 0 ]; then
  usage
  exit 1
fi

eval set -- $OPTS

while true; do
  case "$1" in
    -d|--debug)
      DEBUG=1; shift ;;
    -m|--machine-output)
      MACHINE_OUTPUT=1; shift ;;
    -n|--number)
      NODE_NUMBER=$2; shift 2 ;;
    -s|--scenario)
      SCENARIO=$2; shift 2 ;;
    -f|--fullnodes-number)
      FULL_NODES=$2 ; shift 2 ;;
    -t|--topology)
      TOPOLOGY=$2 ; shift 2 ;;
    -p|--protocol)
      PROTOCOL=$2 ; shift 2 ;;
    -r|--repository)
      REPO_URL=$2 ; shift 2 ;;
    -b|--branch)
      REPO_BRANCH=$2 ; shift 2 ;;
    -a|--api-port)
      API_PORT=$2 ; shift 2 ;;
    -g|--gossip-tcp)
      GOSSIP_TCP_PORT=$2 ; shift 2 ;;
    -u|--gossip-udp)
      GOSSIP_UDP_PORT=$2 ; shift 2 ;;
    --)
      shift ; break ;;
    *)
      usage ; exit 1 ;;
  esac
done

if [ $DEBUG -eq 1 ]; then
  set -x
fi

if [ $MACHINE_OUTPUT -eq 1 ]; then
  exec 3>&1
  exec 1>/dev/null
fi

check_opts

if [ -d docker/iri ]; then
  cd docker/iri
  git fetch --all
  git checkout origin/$REPO_BRANCH 2>/dev/null
  cd ../..
else
  git clone --depth 1 --branch $REPO_BRANCH $REPO_URL docker/iri 2>/dev/null
fi

cd docker/iri
REVISION=$(git rev-parse HEAD)
cd ..

print_message --------------------------
print_message "Deploying revision $REVISION"
print_message --------------------------

if [ $(curl -s -w "%{http_code}" https://registry.hub.docker.com/v2/repositories/$DOCKER_REGISTRY/tags/$REVISION/ -o /dev/null) != '200' ]; then
  if [ $(docker images | grep $DOCKER_REGISTRY | grep -c $REVISION) -eq 0 ]; then
    sed "s/API_PORT_PLACEHOLDER/$API_PORT/g" <Dockerfile |
      docker build -f - -t $DOCKER_REGISTRY:$REVISION .
  fi 
  docker push $DOCKER_REGISTRY:$REVISION 
fi

cd ..

IRI_TARGETS_JSON_FILE=$(mktemp)
PROMETHEUS_CONFIG_DIR=$(mktemp -d)
TANGLESCOPE_CONFIG_DIR=$(mktemp -d)

sed "s/API_PORT_PLACEHOLDER/$API_PORT/g" <configs/tanglescope.yml >$TANGLESCOPE_CONFIG_DIR/tanglescope.yml
kubectl create configmap tanglescope-$REVISION --from-file $TANGLESCOPE_CONFIG_DIR/tanglescope.yml

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
      sed "s/API_PORT_PLACEHOLDER/$API_PORT/g" |
      sed "s/GOSSIP_TCP_PORT_PLACEHOLDER/$GOSSIP_TCP_PORT/g" |
      sed "s/GOSSIP_UDP_PORT_PLACEHOLDER/$GOSSIP_UDP_PORT/g" |
      kubectl create -f -
  else
    sed "s/NODE_NUMBER_PLACEHOLDER/$node_num/" <iri-tanglescope.yml |
      sed "s#IRI_IMAGE_PLACEHOLDER#$DOCKER_REGISTRY:$REVISION#" |
      sed "s/REVISION_PLACEHOLDER/$REVISION/g" |
      sed 's/ISFULL_PLACEHOLDER/"false"/g' |
      sed 's#IRI_DB_URL_PLACEHOLDER#""#g' |
      sed "s/API_PORT_PLACEHOLDER/$API_PORT/g" |
      sed "s/GOSSIP_TCP_PORT_PLACEHOLDER/$GOSSIP_TCP_PORT/g" |
      sed "s/GOSSIP_UDP_PORT_PLACEHOLDER/$GOSSIP_UDP_PORT/g" |
      kubectl create -f -
  fi
done

print_message --------------------------
print_message "Waiting until IRIs pods are up"
print_message --------------------------

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

print_message --------------------------
print_message "Waiting until Grafana is healthy"

while kubectl get pods -l app=grafana,revision=$REVISION | tail -n+2 | grep -v Running >/dev/null; do
  sleep 5
done

GRAFANA_ENDPOINT=$(kubectl get service grafana-$REVISION -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
while [ $GRAFANA_ENDPOINT = 'null' -o -z $GRAFANA_ENDPOINT ]; do
  GRAFANA_ENDPOINT=$(kubectl get service grafana-$REVISION -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
done

while ! curl -s -o /dev/null "http://$GRAFANA_ENDPOINT/api/datasources" \
  --user admin:admin -H 'X-Grafana-Org-Id: 1' -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"Prometheus","isDefault":true,"type":"prometheus","url":"http://localhost:9090","access":"proxy","jsonData":{"keepCookies":[],"httpMethod":"GET"},"secureJsonFields":{}}'
do
  sleep 1
done

IFS=' ' read -a IRI_APIS <<<$(kubectl get service -l app=iri,revision=$REVISION -o json | jq -r '[ .items[].status.loadBalancer.ingress[0].hostname ] | join(" ")')

print_message "You can now connect to Grafana at http://$GRAFANA_ENDPOINT with admin:admin"
print_message "IRI API Endpoints:"
for i in "${!IRI_APIS[@]}"; do
  print_message -e "\t - http://${IRI_APIS[$i]}:$API_PORT"
done

print_message "Waiting until IRIs are healthy"
for iri_api in "${IRI_APIS[@]}"; do
  wait_until_iri_api_healthy $iri_api
done

print_message "Configuring nodes topology..."

IFS=' ' read -a IRI_IPS <<<$(jq -r '.iri_targets | join(" ")' <$IRI_TARGETS_JSON_FILE)

if [ $TOPOLOGY -eq 1 ]; then
  all_to_all_topology IRI_APIS[@] IRI_IPS[@]
else
  chain_topology IRI_APIS[@] IRI_IPS[@]
fi

print_message "All done bro!"
print_message --------------------------

if [ $MACHINE_OUTPUT -eq 1 ]; then
  {
    printf '{"iris": ['
    for i in $(seq 0 $((${#IRI_APIS[@]} - 1))); do
      printf '{"api": "%s", "api_port": "%s", "gossip": "%s", "gossip_tcp_port": "%s", "gossip_udp_port": "%s"}' \
        ${IRI_APIS[$i]} $API_PORT ${IRI_IPS[$i]} $GOSSIP_TCP_PORT $GOSSIP_UDP_PORT
      if [ $i != $((${#IRI_APIS[@]} - 1)) ]; then
        printf ','
      fi
    done
    printf '],'
    printf '"grafana": {"endpoint": "%s", "port": "%s"}}' $GRAFANA_ENDPOINT 80
  } >&3
fi
