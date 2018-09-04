#!/usr/bin/env python

from __future__ import print_function

import re
import json
import yaml
import os
import sys
import copy
import time
import subprocess
import requests
import kubernetes
from uuid import uuid4
from getopt import getopt
from jinja2 import Template

api_headers = {
                'X-IOTA-API-Version': '1',
                'Content-Type': 'application/json'
              }

def print_message(s):
    if debug:
        print('[+] %s' % str(s).rstrip())

def die(s):
    print(s, file = sys.stderr)
    sys.exit(2)

def success(output, cluster):
    output.write(yaml.dump(cluster, default_flow_style = False))
    sys.exit(0)

def fail(output, cluster):
    output.write(yaml.dump(cluster, default_flow_style = False))
    sys.exit(2)

def usage():
    die('''     %s -i repo/image:latest -c cluster.yml -o output.yml [-k kube.config] [-d --debug]
    
                # -i / --image              Docker IRI image to use, relative to Hub
                # -c / --cluster            cluster definition in YAML format
                # -o / --output             output file for node information in YAML format
                # -k / --kubeconfig         Path of the kubectl config file to access the K8S cluster
                # -d / --debug              print debug information
        ''' % __file__)
    sys.exit(2)

def parse_opts(opts):
    global docker_image, kubeconfig, cluster, output, debug
    if len(opts[0]) == 0:
        usage()
    for (key, value) in opts:
        if key == '-i' or key == '--image':
            docker_image = value
        elif key == '-c' or key == '--cluster':
            cluster = value
        elif key == '-o' or key == '--output':
            output = value
        elif key == '-k' or key == '--kubeconfig':
            kubeconfig = value
        elif key == '-d' or key == '--debug':
            debug = True
        else:
            usage()
    if not docker_image or not cluster or not output:
        usage()

def add_node_neighbor(node, protocol, host, port):
    url = 'http://%s:%s' % (node['host'], node['ports']['api'])
    payload = {
                'command': 'addNeighbors',
                'uris': ['%s://%s:%s' % (protocol, host, port)]
              }
    requests.post(url, headers = api_headers, data = json.dumps(payload))

def add_node_mutual_neighbor(nodeA, nodeB):
    add_node_neighbor(nodeA, nodeB)
    add_node_neighbor(nodeB, nodeA)

def chain_topology(nodes):
    for i in range(0, len(nodes) - 1):
        add_node_mutual_neighbor(nodes[i], nodes[i + 1])
    
def all_to_all_topology():
    for i in range(0, len(nodes)):
        for j in range(i + 1, len(nodes)):
            add_node_mutual_neighbor(nodes[i], nodes[j])

def wait_until_iri_api_is_healthy(node):
    url = 'http://%s:%s' % (node.api, node.api_port)
    payload = {
                'command': 'getNodeInfo'
              }
    try:
        requests.post(url, headers = api_headers, data = json.dumps(payload), timeout = 5)
    except:
        time.sleep(1)

def validate_cluster(cluster):
    pass

def init_k8s_client():
    kubernetes.config.load_kube_config(config_file = kubeconfig)
    return kubernetes.client.CoreV1Api()

def wait_until_pod_ready(kubernetes_client, namespace, pod_name, timeout = 60):
    for _ in range(0, timeout):
        pod = kubernetes_client.read_namespaced_pod(pod_name, namespace)
        if pod.status.phase == 'Failed':
            break
        try:
            if reduce(lambda ready, container: ready and container.ready, pod.status.container_statuses, True):
                return pod
        except TypeError:
            pass
        finally:
            time.sleep(1)
    raise RuntimeError('Pod did not start correctly.')

def deploy_monitoring(kubernetes_client, cluster):
    with open('configs/tanglescope.j2', 'r') as stream:
        tanglescope_config_template = Template(stream.read())
    with open('configs/tanglescope-configmap.j2', 'r') as stream:
        tanglescope_configmap_template = Template(stream.read())
    with open('configs/tanglescope-pod.j2', 'r') as stream:
        tanglescope_pod_template = Template(stream.read())
    with open('configs/tanglescope-clusterip.j2', 'r') as stream:
        tanglescope_clusterip_template = Template(stream.read())
    with open('configs/prometheus.j2', 'r') as stream:
        prometheus_config_template = Template(stream.read())
    with open('configs/prometheus-configmap.j2', 'r') as stream:
        prometheus_configmap_template = Template(stream.read())
    with open('configs/prometheus-grafana-pod.j2', 'r') as stream:
        prometheus_grafana_pod_template = Template(stream.read())
    with open('configs/prometheus-grafana-service.j2', 'r') as stream:
        prometheus_grafana_service_template = Template(stream.read())
    for node in cluster['nodes'].keys():
        tanglescope_config = tanglescope_config_template.render(iri_target = cluster['nodes'][node]['clusterip'])
        tanglescope_configmap_resource = yaml.load(tanglescope_configmap_template.render(
            REVISION_PLACEHOLDER = cluster['revision_hash'],
            NODE_UUID_PLACEHOLDER = cluster['nodes'][node]['uuid']
        ))
        tanglescope_pod_resource = yaml.load(tanglescope_pod_template.render(
            REVISION_PLACEHOLDER = cluster['revision_hash'],
            NODE_UUID_PLACEHOLDER = cluster['nodes'][node]['uuid']
        ))
        tanglescope_clusterip_resource = yaml.load(tanglescope_clusterip_template.render(
            REVISION_PLACEHOLDER = cluster['revision_hash'],
            NODE_UUID_PLACEHOLDER = cluster['nodes'][node]['uuid']
        ))
        tanglescope_configmap_resource['data']['tanglescope.yml'] = tanglescope_config
        kubernetes_client.create_namespaced_config_map('default', tanglescope_configmap_resource, pretty = True)
        pod = kubernetes_client.create_namespaced_pod('default', tanglescope_pod_resource, pretty = True)
        clusterip = kubernetes_client.create_namespaced_service('default', tanglescope_clusterip_resource, pretty = True)

        cluster['nodes'][node]['tanglescope_podname'] = pod.metadata.name
        cluster['nodes'][node]['tanglescope_clusteripname'] = clusterip.metadata.name
        cluster['nodes'][node]['tanglescope_clusterip'] = clusterip.spec.cluster_ip
        cluster['nodes'][node]['tanglescope_clusterip_ports'] = { p.name: p.port for p in clusterip.spec.ports }

    prometheus_config = prometheus_config_template.render(
        iri_targets = [ properties['clusterip'] for (_, properties) in cluster['nodes'].iteritems() ],
        tanglescope_targets = [ properties['tanglescope_clusterip'] for (_, properties) in cluster['nodes'].iteritems() ]
    )
    prometheus_configmap_resource = yaml.load(prometheus_configmap_template.render(
        REVISION_PLACEHOLDER = cluster['revision_hash']
    ))
    prometheus_grafana_pod_resource = yaml.load(prometheus_grafana_pod_template.render(
        REVISION_PLACEHOLDER = cluster['revision_hash']
    ))
    prometheus_grafana_service_resource = yaml.load(prometheus_grafana_service_template.render(
        REVISION_PLACEHOLDER = cluster['revision_hash']
    ))
    prometheus_configmap_resource['data']['prometheus.yml'] = prometheus_config
    kubernetes_client.create_namespaced_config_map('default', prometheus_configmap_resource, pretty = True)
    pod = kubernetes_client.create_namespaced_pod('default', prometheus_grafana_pod_resource, pretty = True)
    service = kubernetes_client.create_namespaced_service('default', prometheus_grafana_service_resource, pretty = True)

    cluster['grafana_podname'] = pod.metadata.name
    cluster['grafana_servicename'] = service.metadata.name
    cluster['grafana_port'] = service.spec.ports[0].node_port

    pod = wait_until_pod_ready(kubernetes_client, 'default', cluster['grafana_podname'])
    cluster['grafana_host'] = pod.spec.node_name

    url = 'http://%s:%s/api/datasources' % (cluster['grafana_host'], cluster['grafana_port'])
    headers = {
                'X-Grafana-Org-Id': '1',
                'Content-Type': 'application/json;charset=UTF-8'
              }
    payload = {
                'name': 'Prometheus',
                'isDefault': True,
                'type': 'prometheus',
                'url': 'http://localhost:9090',
                'access': 'proxy',
                'jsonData': { 'keepCookies': [], 'httpMethod': 'GET' },
                'secureJsonFields': {}
              }
    requests.post(url, auth = ('admin', 'admin'), headers = headers, data = json.dumps(payload))

docker_image = None
kubeconfig = None
debug = False
cluster = None
output = None
healthy = True

if __name__ == '__main__':
    try:
        opts = getopt(sys.argv[1:], 'i:k:c:o:d', ['image=', 'kubeconfig=', 'cluster=', 'output=', 'debug'])
        parse_opts(opts[0])
    except:
        usage()

    with open(cluster, 'r') as stream:
        try:
            cluster = yaml.load(stream)
        except yaml.YAMLError as e:
            die(e)
    try:
        output = open(output, 'w')
    except Exception as e:
        die(e)

    os.chdir(os.path.dirname(os.path.realpath(__file__)))
    validate_cluster(cluster)
    print_message("Initializing kubernetes client library against cluster")
    kubernetes_client = init_k8s_client()
    with open('configs/iri-pod.j2', 'r') as stream:
        iri_pod_template = Template(stream.read())
    with open('configs/iri-service.j2', 'r') as stream:
        iri_service_template = Template(stream.read())
    with open('configs/iri-clusterip.j2', 'r') as stream:
        iri_clusterip_template = Template(stream.read())

    for (node, properties) in cluster['nodes'].iteritems():
        node_uuid = str(uuid4())
        service_resource = yaml.load(iri_service_template.render(
            REVISION_PLACEHOLDER = revision_hash,
            NODE_NUMBER_PLACEHOLDER = node.lower(),
            NODE_UUID_PLACEHOLDER = node_uuid
        ))
        clusterip_resource = yaml.load(iri_clusterip_template.render(
            REVISION_PLACEHOLDER = revision_hash,
            NODE_NUMBER_PLACEHOLDER = node.lower(),
            NODE_UUID_PLACEHOLDER = node_uuid
        ))

        try:
            db_checksum = properties['db_checksum']
        except KeyError:
            db_checksum = ''

        pod_resource = yaml.load(iri_pod_template.render(
            REVISION_PLACEHOLDER = revision_hash,
            IRI_IMAGE_PLACEHOLDER = docker_image,
            NODE_NUMBER_PLACEHOLDER = node.lower(),
            IRI_DB_URL_PLACEHOLDER = properties['db'],
            IRI_DB_CHECKSUM_PLACEHOLDER = db_checksum,
            NODE_UUID_PLACEHOLDER = node_uuid
        ))

        print_message("Deploying %s" % node)
        pod = kubernetes_client.create_namespaced_pod('default', pod_resource, pretty = True)
        service = kubernetes_client.create_namespaced_service('default', service_resource, pretty = True)
        clusterip = kubernetes_client.create_namespaced_service('default', clusterip_resource, pretty = True)

        cluster['nodes'][node]['uuid'] = node_uuid
        cluster['nodes'][node]['podname'] = pod.metadata.name
        cluster['nodes'][node]['servicename'] = service.metadata.name
        cluster['nodes'][node]['clusteripname'] = clusterip.metadata.name
        cluster['nodes'][node]['ports'] = { p.name: p.node_port for p in service.spec.ports }
        cluster['nodes'][node]['clusterip'] = clusterip.spec.cluster_ip
        cluster['nodes'][node]['clusterip_ports'] = { p.name: p.port for p in clusterip.spec.ports }

    try:
        if cluster['monitoring']:
            deploy_monitoring(kubernetes_client, cluster)
    except KeyError:
        pass

    for node in cluster['nodes'].keys():
        try:
            pod = wait_until_pod_ready(kubernetes_client, 'default', cluster['nodes'][node]['podname'])
        except RuntimeError:
            healthy = False
            cluster['nodes'][node]['status'] = 'Error'
        else:
            cluster['nodes'][node]['host'] = pod.spec.node_name
            cluster['nodes'][node]['status'] = 'Running'
            for neighbor in cluster['nodes'][node]['neighbors']:
                m = re.match('^([a-z]+?)://([^:]+?):(\d+)$', neighbor)
                protocol = m.group(1)
                host = m.group(2)
                port = m.group(3)
                if host in cluster['nodes'].keys():
                    host = cluster['nodes'][host]['clusterip']
                add_node_neighbor(cluster['nodes'][node], protocol, host, port)
        finally:
            cluster['nodes'][node]['log'] = kubernetes_client.read_namespaced_pod_log(cluster['nodes'][node]['podname'], 'default', pretty = True)

    if healthy:
        success(output, cluster)
    else:
        fail(output, cluster)
