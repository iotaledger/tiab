#!/usr/bin/env python

from __future__ import print_function

import json
import yaml
import os
import sys
import copy
import time
import subprocess
import requests
import docker
import kubernetes
from getopt import getopt

api_headers = {
                'Content-Type': 'application/json',
                'X-IOTA-API-Version': 1
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
    die('''     %s [-r iri repository] [-b iri branch] [-u docker registry] [-d --debug] -c cluster.yml -o output.yml
    
                # -r / --repository         IRI repository to use
                # -b / --branch             branch to test
                # -d / --debug              print debug information
                # -c / --cluster            cluster definition in YAML format
                # -u / --docker-registry    docker Hub relative path to upload IRI images
                # -o / --output             output file for node information in YAML format
        ''' % __file__)
    sys.exit(2)

def parse_opts(opts):
    global repository, branch, debug, machine, cluster, output, docker_registry
    if len(opts[0]) == 0:
        usage()
    for (key, value) in opts:
        if key == '-r' or key == '--repository':
            repository = value
        elif key == '-b' or key == '--branch':
            branch = value
        elif key == '-d' or key == '--debug':
            debug = True
        elif key == '-c' or key == '--cluster':
            cluster = value
        elif key == '-o' or key == '--output':
            output = value
        elif key == '-u' or key == '--docker-registry':
            docker_registry = value
        else:
            usage()
    if not cluster or not output:
        usage()

def add_node_neighbor(node, neighbor):
    url = 'http://%s:%s' % (node.api, node.api_port)
    payload = {
                'command': 'addNeighbors',
                'uris': ['%s://%s:%s' % (cluster['protocol'], neighbor.gossip, neighbor.gossip_port)]
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

def checkout_iri(repository, branch):
    if os.path.isdir('docker/iri'):
        os.system('(cd docker/iri; git fetch --all; git checkout origin/%s) 2>&1' % branch)
    else:
        os.system('(git clone --depth 1 --branch %s %s docker/iri) 2>&1' % (branch, repository))
    result = subprocess.Popen('cd docker/iri; git rev-parse HEAD', shell = True, stdout = subprocess.PIPE)
    return result.stdout.readlines()[0].rstrip()

def is_image_in_docker_registry(registry, revision_hash):
    url = 'https://registry.hub.docker.com/v2/repositories/%s/tags/%s/' % (registry, revision_hash)
    return requests.get(url).status_code == 200

def validate_cluster(cluster):
    pass

def init_k8s_client():
    kubernetes.config.load_kube_config()
    return kubernetes.client.CoreV1Api()

def deep_map(obj, func):
    _obj = copy.deepcopy(obj)
    if type(_obj) == dict:
        for key in _obj.keys():
            _obj[key] = deep_map(_obj[key], func)
    elif type(_obj) == list:
        for i, _ in enumerate(_obj):
            _obj[i] = deep_map(_obj[i], func)
    else:
        _obj = func(_obj)
    return _obj

def fill_template_property(template, placeholder, value):
    return deep_map(template, lambda s: s.replace(placeholder, value) if isinstance(s, str) else s)

def wait_until_pod_ready(kubernetes_client, namespace, pod_name, timeout = 60):
    for _ in range(0, timeout):
        pod = kubernetes_client.read_namespaced_pod(pod_name, namespace)
        if pod.status.phase == 'Failed':
            break
        if pod.status.container_statuses[0].ready:
            return pod
        time.sleep(1)
    raise RuntimeError('Pod did not start correctly.')

repository = 'https://github.com/iotaledger/iri.git'
branch = 'dev'
docker_registry = 'karimo/iri-network-tests'
debug = False
cluster = None
output = None
healthy = True

if __name__ == '__main__':
    opts = getopt(sys.argv[1:], 'r:b:dc:o:u:', ['repository=', 'branch=', 'debug', 'cluster=', 'output=', 'docker-registry='])
    parse_opts(opts[0])

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
    print_message("Checking out IRI")
    revision_hash = checkout_iri(repository, branch)
    cluster['revision_hash'] = revision_hash
    print_message("Revision is %s" % revision_hash)
    if not is_image_in_docker_registry(docker_registry, revision_hash):
        docker_client = docker.from_env()
        try:
            docker_client.images.get('%s:%s' % (docker_registry, revision_hash))
        except docker.errors.ImageNotFound:
            print_message("Building docker image")
            # Build process is really "loud"
            for line in docker_client.api.build(path = 'docker', tag = '%s:%s' % (docker_registry, revision_hash)):
                try:
                    print_message(json.loads(line)['stream'])
                except KeyError:
                    print_message(json.loads(line))

        print_message("Pushing docker image to %s" % docker_registry)
        for line in docker_client.images.push(docker_registry, revision_hash, stream = True):
            try:
                print_message(json.loads(line)['status'])
            except KeyError:
                print_message(json.loads(line))

    print_message("Initializing kubernetes client library against cluster")
    kubernetes_client = init_k8s_client()
    with open('iri-pod.yml', 'r') as stream:
        iri_pod_template = yaml.load(stream)
    with open('iri-service.yml', 'r') as stream:
        iri_service_template = yaml.load(stream)

    iri_pod_template = fill_template_property(iri_pod_template, 'REVISION_PLACEHOLDER', revision_hash)
    iri_pod_template = fill_template_property(iri_pod_template, 'IRI_IMAGE_PLACEHOLDER', '%s:%s' % (docker_registry, revision_hash))
    iri_service_template = fill_template_property(iri_service_template, 'REVISION_PLACEHOLDER', revision_hash)

    for (node, properties) in cluster['nodes'].iteritems():
        node_resource = fill_template_property(iri_pod_template, 'NODE_NUMBER_PLACEHOLDER', node.lower())
        service_resource = fill_template_property(iri_service_template, 'NODE_NUMBER_PLACEHOLDER', node.lower())
        node_resource = fill_template_property(node_resource, 'IRI_DB_URL_PLACEHOLDER', properties['db'])
        node_resource = fill_template_property(node_resource, 'IRI_DB_CHECKSUM_PLACEHOLDER', properties['db_checksum'])

        print_message("Deploying %s" % node)
        pod = kubernetes_client.create_namespaced_pod('default', node_resource, pretty = True)
        service = kubernetes_client.create_namespaced_service('default', service_resource, pretty = True)
        
        cluster['nodes'][node]['podname'] = pod.metadata.name
        cluster['nodes'][node]['servicename'] = service.metadata.name
        cluster['nodes'][node]['ports'] = { p.name: p.node_port for p in service.spec.ports }

    for node in cluster['nodes'].keys():
        try:
            pod = wait_until_pod_ready(kubernetes_client, 'default', cluster['nodes'][node]['podname'])
        except RuntimeError:
            healthy = False
            cluster['nodes'][node]['status'] = 'Error'
        else:
            cluster['nodes'][node]['host'] = pod.spec.node_name
            cluster['nodes'][node]['status'] = 'Running'
        finally:
            cluster['nodes'][node]['log'] = kubernetes_client.read_namespaced_pod_log(cluster['nodes'][node]['podname'], 'default', pretty = True)

    if healthy:
        success(output, cluster)
    else:
        fail(output, cluster)
