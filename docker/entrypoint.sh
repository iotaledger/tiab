#!/bin/bash
# See Dockerfile and DOCKER.md for further info

if [ "${DOCKER_IRI_MONITORING_API_PORT_ENABLE}" == "1" ]; then
  nohup socat -lm TCP-LISTEN:14266,fork TCP:127.0.0.1:${DOCKER_IRI_MONITORING_API_PORT_DESTINATION} &
fi

MEM_GB=$(printf %.1s $(free -m | tail -n+2 | head -n-1 | awk -F' ' '{ print $2 }'))

exec java \
  $JAVA_OPTIONS \
  -Xms$(expr $MEM_GB / 2) \
  -Xmx$MEM_GB \
  -Djava.net.preferIPv4Stack=true \
  -Dcom.sun.management.jmxremote.* \
  -jar $DOCKER_IRI_JAR_PATH \
  --remote \
  "$@"
