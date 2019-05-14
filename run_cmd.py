#!/usr/bin/env python


from yaml import load, Loader
from kubernetes import config
from kubernetes.client.apis import core_v1_api
#from kubernetes.client.rest import ApiException
from kubernetes.stream import stream

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('-k', '--kubeconfig', dest='kubeconfig', required=True)
parser.add_argument('-o', '--output', dest='output', required=True)
parser.add_argument('-n', '--namespace', dest='namespace', required=True)
parser.add_argument('-d', '--node', nargs='+', dest='node_name')
parser.add_argument('-c', '--command', dest='command', required=True)

args = parser.parse_args()
kubeconfig = args.kubeconfig
output = args.output
namespace = args.namespace
node_name = args.node_name
command = args.command

def init_k8s_client():
    config.load_kube_config(config_file = kubeconfig)
    return core_v1_api.CoreV1Api()

def get_nodes(yaml_file):
    nodes = []
    for key in yaml_file['nodes']:
        nodes.append(key)
    return nodes

def get_podnames(yaml_file, nodes):
    names = {}
    for node in nodes:
        names[node] =  yaml_file['nodes'][node]['podname']
    return names

def exec_cmd(kubernetes_client, podname, namespace, command): 
    exec_command = ['/bin/bash', '-c', command] 
    resp = stream(kubernetes_client.connect_get_namespaced_pod_exec, podname, namespace,
                  command=exec_command,
                  stderr=True, stdin=False,
                  stdout=True, tty=False)
    return resp

def main():
    stream = open(output,'r')
    output_stream = load(stream,Loader=Loader)
    namespace = 'buildkite'
    kubernetes_client = init_k8s_client()
    names = {}
    if node_name: 
        names = get_podnames(output_stream, node_name)
    else: 
        names = get_podnames(output_stream, get_nodes(output_stream))
    for node, podname in names.items():
        print('{} :\n {}'.format(node, exec_cmd(kubernetes_client, podname, namespace, command)), end='')

if __name__ == '__main__':
    main()


