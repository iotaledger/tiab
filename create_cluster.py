#!/usr/bin/env python

from __future__ import print_function

import re
import json
import yaml
import os
import sys
import copy
import time
import tarfile
import requests
import kubernetes
from uuid import uuid4
from getopt import getopt
from jinja2 import Template
from tempfile import TemporaryFile
from functools import reduce

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
    die('''     %s -i repo/image:latest -t tag -c cluster.yml -o output.yml [-k kube.config] [-n namespace] [-d --debug]
    
                # -i / --image              Docker IRI image to use, relative to Hub
                # -t / --tag                ID to tag the deployment with
                # -c / --cluster            cluster definition in YAML format
                # -o / --output             output file for node information in YAML format
                # -n / --namespace          Kubernetes namespace to use for your cluster deployment
                # -k / --kubeconfig         Path of the kubectl config file to access the K8S cluster
                # -x / --ixis               Base path for IXI modules to be specified in cluster configuration
                # -e / --extras             Additional commands to be run at pod creation
                # -d / --debug              print debug information
        ''' % __file__)

def parse_opts(opts):
    global docker_image, tag, kubeconfig, cluster, output, debug, namespace, ixis_path, extras_cmd
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
        elif key == '-t' or key == '--tag':
            tag = value
        elif key == '-n' or key == '--namespace':
            namespace = value
        elif key == '-x' or key == '--ixis':
            ixis_path = value
        elif key == '-e' or key == '--extras':
            extras_cmd = value
        elif key == '-d' or key == '--debug':
            debug = True
        else:
            usage()
    if not docker_image or not tag or not cluster or not output:
        usage()

def add_node_neighbor(node, protocol, host, port):
    url = 'http://%s:%s' % (node['host'], node['ports']['api'])
    payload = {
                'command': 'addNeighbors',
                'uris': ['%s://%s:%s' % (protocol, host, port)]
              }
    requests.post(url, headers = api_headers, data = json.dumps(payload))

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

def wait_until_pod_running(kubernetes_client, namespace, pod_name, timeout = 600):
    for _ in range(0, timeout):
        pod = kubernetes_client.read_namespaced_pod(pod_name, namespace)
        if pod.status.phase == 'Running':
            return True
        elif pod.status.phase == 'Failed':
            break
        time.sleep(1)
    raise RuntimeError('Pod did not run correctly.')

def wait_until_pod_ready(kubernetes_client, namespace, pod_name, timeout = 600):
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

def make_tarfile(source_dir):
    with TemporaryFile() as tar_buffer:
        with tarfile.open(fileobj = tar_buffer, mode = "w:gz") as tar:
            tar.add(os.path.join(ixis_path, source_dir), arcname = os.path.basename(source_dir))
        tar_buffer.seek(0)
        return tar_buffer.read()

def upload_ixi_modules(kubernetes_client, node):
    # This command will extract the uploaded archive, making also sure the extracted directory name is stripped from the .ixi suffix.
    upload_command = ['tar', 'zxvf', '-', '-C', '/iri/data/ixi', '--transform', 's/.ixi//']
    wait_until_pod_running(kubernetes_client, namespace, node['podname'])
    kubernetes.stream.stream(kubernetes_client.connect_get_namespaced_pod_exec,
                              node['podname'],
                              namespace,
                              command = [ 'mkdir', '-p', '/iri/data/ixi' ],
                              stderr = False, stdin = False,
                              stdout = True, tty = False
                            )

    for ixi_path in node['upload_ixis_paths']:
        print_message("Uploading IXI path %s to %s" % (ixi_path, node['podname']))
        upload_data = make_tarfile(ixi_path)
        socket = kubernetes.stream.stream(kubernetes_client.connect_get_namespaced_pod_exec,
                                           node['podname'],
                                           namespace,
                                           command = upload_command,
                                           stderr = True, stdin = True,
                                           stdout = True, tty = False,
                                           _preload_content = False
                                         )
        socket.write_stdin(upload_data)
        socket.close()

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
            TAG_PLACEHOLDER = tag,
            NODE_UUID_PLACEHOLDER = cluster['nodes'][node]['uuid']
        ), Loader = yaml.SafeLoader)
        tanglescope_pod_resource = yaml.load(tanglescope_pod_template.render(
            TAG_PLACEHOLDER = tag,
            NODE_UUID_PLACEHOLDER = cluster['nodes'][node]['uuid']
        ), Loader = yaml.SafeLoader)
        tanglescope_clusterip_resource = yaml.load(tanglescope_clusterip_template.render(
            TAG_PLACEHOLDER = tag,
            NODE_UUID_PLACEHOLDER = cluster['nodes'][node]['uuid']
        ), Loader = yaml.SafeLoader)
        tanglescope_configmap_resource['data']['tanglescope.yml'] = tanglescope_config
        kubernetes_client.create_namespaced_config_map(namespace, tanglescope_configmap_resource, pretty = True)
        pod = kubernetes_client.create_namespaced_pod(namespace, tanglescope_pod_resource, pretty = True)
        clusterip = kubernetes_client.create_namespaced_service(namespace, tanglescope_clusterip_resource, pretty = True)

        cluster['nodes'][node]['tanglescope_podname'] = pod.metadata.name
        cluster['nodes'][node]['tanglescope_clusteripname'] = clusterip.metadata.name
        cluster['nodes'][node]['tanglescope_clusterip'] = clusterip.spec.cluster_ip
        cluster['nodes'][node]['tanglescope_clusterip_ports'] = { p.name: p.port for p in clusterip.spec.ports }

    prometheus_config = prometheus_config_template.render(
        iri_targets = [ properties['clusterip'] for (_, properties) in cluster['nodes'].items() ],
        tanglescope_targets = [ properties['tanglescope_clusterip'] for (_, properties) in cluster['nodes'].items() ]
    )
    prometheus_configmap_resource = yaml.load(prometheus_configmap_template.render(
        TAG_PLACEHOLDER = tag
    ), Loader = yaml.SafeLoader)
    prometheus_grafana_pod_resource = yaml.load(prometheus_grafana_pod_template.render(
        TAG_PLACEHOLDER = tag
    ), Loader = yaml.SafeLoader)
    prometheus_grafana_service_resource = yaml.load(prometheus_grafana_service_template.render(
        TAG_PLACEHOLDER = tag
    ), Loader = yaml.SafeLoader)
    prometheus_configmap_resource['data']['prometheus.yml'] = prometheus_config
    kubernetes_client.create_namespaced_config_map(namespace, prometheus_configmap_resource, pretty = True)
    pod = kubernetes_client.create_namespaced_pod(namespace, prometheus_grafana_pod_resource, pretty = True)
    service = kubernetes_client.create_namespaced_service(namespace, prometheus_grafana_service_resource, pretty = True)

    cluster['grafana_podname'] = pod.metadata.name
    cluster['grafana_servicename'] = service.metadata.name
    cluster['grafana_port'] = service.spec.ports[0].node_port

    pod = wait_until_pod_ready(kubernetes_client, namespace, cluster['grafana_podname'])
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
namespace = 'default'
tag = None
kubeconfig = None
debug = False
cluster = None
output = None
ixis_path = os.getcwd()
healthy = True
extras_cmd = None

if __name__ == '__main__':
    try:
        opts = getopt(sys.argv[1:], 'i:t:k:c:n:o:x:e:d', ['image=', 'tag=', 'kubeconfig=', 'cluster=', 'namespace=', 'output=', 'ixis=', 'extras=','debug'])
        parse_opts(opts[0])
    except:
        usage()

    with open(cluster, 'r') as stream:
        try:
            cluster = yaml.load(stream, Loader = yaml.SafeLoader)
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
    with open('configs/tiab-entrypoint-configmap.j2', 'r') as stream:
        tiab_entrypoint_configmap_template = Template(stream.read())
    with open('configs/iri-service.j2', 'r') as stream:
        iri_service_template = Template(stream.read())
    with open('configs/iri-clusterip.j2', 'r') as stream:
        iri_clusterip_template = Template(stream.read())

    tiab_entrypoint_configmap_resource = yaml.load(tiab_entrypoint_configmap_template.render(
        TAG_PLACEHOLDER = tag,
        EXTRAS_COMMANDS_PLACEHOLDER = extras_cmd if extras_cmd else ''
    ), Loader = yaml.SafeLoader)

    try:
        kubernetes_client.create_namespaced_config_map(namespace, tiab_entrypoint_configmap_resource, pretty = True)
    except kubernetes.client.rest.ApiException as e:
        if json.loads(e.body)['reason'] != 'AlreadyExists': raise e

    http_url_regex = re.compile('https?://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]')

    for (node, properties) in cluster['nodes'].items():
        node_uuid = str(uuid4())
        iri_service_resource = yaml.load(iri_service_template.render(
            TAG_PLACEHOLDER = tag,
            NODE_NUMBER_PLACEHOLDER = node.lower(),
            NODE_UUID_PLACEHOLDER = node_uuid
        ), Loader = yaml.SafeLoader)
        iri_clusterip_resource = yaml.load(iri_clusterip_template.render(
            TAG_PLACEHOLDER = tag,
            NODE_NUMBER_PLACEHOLDER = node.lower(),
            NODE_UUID_PLACEHOLDER = node_uuid
        ), Loader = yaml.SafeLoader)

        cluster['nodes'][node]['upload_ixis_paths'] = filter(lambda path: not http_url_regex.match(path), properties['ixis']) if 'ixis' in properties else []

        iri_pod_resource = yaml.load(iri_pod_template.render(
            TAG_PLACEHOLDER = tag,
            IRI_IMAGE_PLACEHOLDER = docker_image,
            NODE_NUMBER_PLACEHOLDER = node.lower(),
            IRI_DB_URL_PLACEHOLDER = properties['db'] if 'db' in properties else '',
            IRI_DB_CHECKSUM_PLACEHOLDER = properties['db_checksum'] if 'db_checksum' in properties else '',
            # Pass only the IXI modules that are downloaded URLs
            IXI_URLS_PLACEHOLDER = ' '.join(filter(http_url_regex.match, properties['ixis'])) if 'ixis' in properties else '',
            NODE_UUID_PLACEHOLDER = node_uuid,
            LOCAL_IXIS_PLACEHOLDER = 'xyes' if cluster['nodes'][node]['upload_ixis_paths'] else 'xno'
        ), Loader = yaml.SafeLoader)

        iri_container = [e for e in iri_pod_resource['spec']['containers'] if e['name'] == 'iri'][0]

        iri_args = properties.get('iri_args')
        if type(iri_args) is list:
            iri_container['args'] = iri_args
        elif iri_args is not None:
            raise RuntimeError('iri_args for node %s is not an array' % node)

        java_options = properties.get('java_options')
        if type(java_options) is str:
            [e for e in iri_container['env'] if e['name'] == 'JAVA_OPTIONS'][0]['value'] = java_options
        elif java_options is not None:
            raise RuntimeError('java_options for node %s is not a string' % node)

        print_message("Deploying %s" % node)
        iri_pod = kubernetes_client.create_namespaced_pod(namespace, iri_pod_resource, pretty = True)
        iri_service = kubernetes_client.create_namespaced_service(namespace, iri_service_resource, pretty = True)
        clusterip = kubernetes_client.create_namespaced_service(namespace, iri_clusterip_resource, pretty = True)

        cluster['nodes'][node]['uuid'] = node_uuid
        cluster['nodes'][node]['podname'] = iri_pod.metadata.name
        cluster['nodes'][node]['servicename'] = iri_service.metadata.name
        cluster['nodes'][node]['clusteripname'] = clusterip.metadata.name
        cluster['nodes'][node]['ports'] = { p.name: p.node_port for p in iri_service.spec.ports }
        cluster['nodes'][node]['clusterip'] = clusterip.spec.cluster_ip
        cluster['nodes'][node]['clusterip_ports'] = { p.name: p.port for p in clusterip.spec.ports }

    try:
        if cluster['monitoring']:
            deploy_monitoring(kubernetes_client, cluster)
    except KeyError:
        pass

    for node in cluster['nodes'].keys():
        try:
            if cluster['nodes'][node]['upload_ixis_paths']:
                upload_ixi_modules(kubernetes_client, cluster['nodes'][node])
            pod = wait_until_pod_ready(kubernetes_client, namespace, cluster['nodes'][node]['podname'])
        except RuntimeError:
            healthy = False
            cluster['nodes'][node]['status'] = 'Error'
        else:
            cluster['nodes'][node]['podip'] = pod.status.pod_ip
            cluster['nodes'][node]['host'] = pod.spec.node_name
            cluster['nodes'][node]['status'] = 'Running'
        finally:
            cluster['nodes'][node]['log'] = kubernetes_client.read_namespaced_pod_log(cluster['nodes'][node]['podname'], namespace, pretty = True)

    for node in cluster['nodes'].keys():
        if 'neighbors' in cluster['nodes'][node]:
            for neighbor in cluster['nodes'][node].get('neighbors'):
                m = re.match('^([a-z]+?)://([^:]+?):(\d+)$', neighbor)
                protocol = m.group(1)
                host = m.group(2)
                port = m.group(3)
                if host in cluster['nodes'].keys():
                    host = cluster['nodes'][host]['podip']
                add_node_neighbor(cluster['nodes'][node], protocol, host, port)


    if healthy:
        success(output, cluster)
    else:
        fail(output, cluster)
