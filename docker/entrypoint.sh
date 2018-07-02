#!/bin/bash
# See Dockerfile and DOCKER.md for further info

if [ "${DOCKER_IRI_MONITORING_API_PORT_ENABLE}" == "1" ]; then
  nohup socat -lm TCP-LISTEN:14266,fork TCP:127.0.0.1:${DOCKER_IRI_MONITORING_API_PORT_DESTINATION} &
fi

MEM_GB=$(printf %.1s $(free -m | tail -n+2 | head -n-1 | awk -F' ' '{ print $2 }'))

if [ ! -z $IRI_DB_URL ]; then
  wget $IRI_DB_URL -O /tmp/testnetdb.tgz
  rm -rf /iri/data/testnet*
  tar xfvz /tmp/testnetdb.tgz -C /iri/data/
fi

exec java \
  $JAVA_OPTIONS \
  -Xms$JAVA_MIN_MEMORY \
  -Djava.net.preferIPv4Stack=true \
  -Dcom.sun.management.jmxremote.* \
  -javaagent:/iri/jmx_prometheus_javaagent-0.3.1.jar=5555:/iri/conf/extras/jmx_prom_config.yaml \
  -jar $DOCKER_IRI_JAR_PATH \
  --remote \
  --testnet \
  "$@"
