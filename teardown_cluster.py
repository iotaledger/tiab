#!/usr/bin/env python

from __future__ import print_function

import sys
import kubernetes
from getopt import getopt

def die(s):
    print(s, file = sys.stderr)
    sys.exit(2)

def usage():
    die('''     %s -t deployment-tag [-k kube.config] [-n namespace]
    
                # -n / --namespace          Kubernetes namespace to use for your cluster deployment
                # -t / --tag                Tag of the deployment to tear down
                # -k / --kubeconfig         Path of the kubectl config file to access the K8S cluster
        ''' % __file__)

def parse_opts(opts):
    global tag, kubeconfig, namespace
    if len(opts[0]) == 0:
        usage()
    for (key, value) in opts:
        if key == '-k' or key == '--kubeconfig':
            kubeconfig = value
        elif key == '-t' or key == '--tag':
            tag = value
        elif key == '-n' or key == '--namespace':
            namespace = value
        else:
            usage()
    if not tag:
        usage()

def init_k8s_client():
    kubernetes.config.load_kube_config(config_file = kubeconfig)
    return kubernetes.client.CoreV1Api()

namespace = 'default'
tag = None
kubeconfig = None

try:
    opts = getopt(sys.argv[1:], 'n:t:k:', ['namespace=', 'tag=', 'kubeconfig='])
    parse_opts(opts[0])
except:
    usage()

kubernetes_client = init_k8s_client()

pods = kubernetes_client.list_namespaced_pod(namespace, label_selector = 'tag=%s' % tag)
services = kubernetes_client.list_namespaced_service(namespace, label_selector = 'tag=%s' % tag)
cms = kubernetes_client.list_namespaced_config_map(namespace, label_selector = 'tag=%s' % tag)

pods_names = [ e.metadata.name for e in pods.items ]
services_names = [ e.metadata.name for e in services.items ]
cms_names = [ e.metadata.name for e in cms.items ]

for pod_name in pods_names:
    kubernetes_client.delete_namespaced_pod(pod_name, namespace)

for service_name in services_names:
    kubernetes_client.delete_namespaced_service(service_name, namespace)

for cm_name in cms_names:
    kubernetes_client.delete_namespaced_config_map(cm_name, namespace)

