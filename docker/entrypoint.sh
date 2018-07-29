#!/bin/bash
# See Dockerfile and DOCKER.md for further info

set -x

if [ "${DOCKER_IRI_MONITORING_API_PORT_ENABLE}" == "1" ]; then
  nohup socat -lm TCP-LISTEN:14266,fork TCP:127.0.0.1:${DOCKER_IRI_MONITORING_API_PORT_DESTINATION} &
fi

MEM_GB=$(printf %.1s $(free -m | tail -n+2 | head -n-1 | awk -F' ' '{ print $2 }'))

if [ ! -z $IRI_DB_URL ]; then
  wget $IRI_DB_URL -O /tmp/db.tar
  if [ ! -z $IRI_DB_CHECKSUM ]; then
    if [ $(sha256sum /tmp/db.tar | cut -d' ' -f1) != $IRI_DB_CHECKSUM ]; then
      echo "ERROR: checksum $IRI_DB_CHECKSUM doesn't match downloaded file!" >&2
      exit 2
    fi
  fi
  rm -rf /iri/data/spamnet*
  rm -rf /iri/data/testnet*
  rm -rf /iri/data/mainnet*
  ARCHIVE_SUBPATH=$(tar tfv /tmp/db.tar | grep -F 'db/' | grep -E '^d'  | awk '{print $6}')
  STRIP_COMPONENTS=$(echo $ARCHIVE_SUBPATH | awk -F'/' '{print NF-2}')
  tar xfv /tmp/db.tar --strip-components=$STRIP_COMPONENTS -C /iri/data $ARCHIVE_SUBPATH
  SNAPSHOT_ARCHIVE_SUBPATH=$(tar tfv /tmp/db.tar | grep -F 'snapshot.txt' | awk '{print $6}')
  SNAPSHOT_STRIP_COMPONENTS=$(echo $SNAPSHOT_ARCHIVE_SUBPATH | awk -F'/' '{print NF-1}')
  tar xfv /tmp/db.tar --strip-components=$SNAPSHOT_STRIP_COMPONENTS -C /iri/data $SNAPSHOT_ARCHIVE_SUBPATH
fi

exec java \
  $JAVA_OPTIONS \
  -Xms$JAVA_MIN_MEMORY \
  -Djava.net.preferIPv4Stack=true \
  -Dcom.sun.management.jmxremote.* \
  -javaagent:/iri/jmx_prometheus_javaagent-0.3.1.jar=5555:/iri/conf/extras/jmx_prom_config.yaml \
  -jar $DOCKER_IRI_JAR_PATH \
  --remote \
  -c /iri.ini \
  "$@"
