#!/bin/bash

set -x

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

/entrypoint.sh "$@"
