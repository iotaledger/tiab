# Tangle in a Box
This tool allows automatic deployment of IRI clusters using Kubernetes according to a YAML-formatted configuration file.

The tool will output all the relevant node information into a similarly-formatted YAML file.

## Before you start

You will need a working Kubernetes cluster you want to deploy to and your local kubectl correctly configured to use it.

## Installation

It is advised to install TIAB's dependencies in a Python virtual environment as follows:

```bash
$ virtualenv venv
$ source venv/bin/activate
$ pip install -r requirements.txt
```

## Command line options

```
-i / --image              Docker IRI image to use, relative to Hub
-t / --tag                ID to tag the deployment with
-c / --cluster            cluster definition in YAML format
-o / --output             output file for node information in YAML format
-k / --kubeconfig         Path of the kubectl config file to access the K8S cluster
-d / --debug              print debug information
```

## Configuration Example

```yaml
defaults: &db_1
  db: https://s3.eu-central-1.amazonaws.com/iotaledger-dbfiles/dev/testnet_files.tgz
  db_checksum: 6eaa06d5442416b7b8139e337a1598d2bae6a7f55c2d9d01f8c5dac69c004f75

nodes:
  nodeA: #name
    <<: *db_1
    neighbors:
      - udp://nodeB:14600
      - tcp://bla.com:1234
  
  nodeB:
    <<: *db_1
    neighbors:
      - udp://nodeA:14600

```

### Node configuration

A node definition yaml supports the following properties:

* `neighbors`: an array of neighbors to add to the specific node once started;
* `iri_args`: an array of the arguments to be passed to IRI command line, overriding container's defaults;
* `java_options`: a string of extra JVM options to be passed to the IRI container, overriding container's defaults.

## Example Usage

```bash
$ ./create_cluster.py --image iotacafe/iri-dev:8d32b7c-29 --tag 1.5.3-deployment --cluster config.yml --output output.yml 
```

The resulting `output.yml` file will contain all the data you need to connect to your nodes.

## Teardown a cluster

You can easily destroy all the resources associated to the cluster you just created by using the `teardown_cluster.py` utility, and passing to it the tag you used to deploy the cluster.

```bash
$ ./teardown_cluster.py --tag 1.5.3-deployment
```

## Monitoring capabilities (Alpha)

If the `config.yml` file includes a `monitoring: True` entry, a twin [tanglescope](https://github.com/iotaledger/entangled) pod will be deployed along every IRI node. Tanglescope wil be responsible to obtain any sort of metrics on the node and serve them to a central Grafana Pod, using Prometheus as a database backend.


