local t = import 'jsonnet/kube-thanos/thanos.libsonnet';

// For an example with every option and component, please check all.jsonnet

local commonConfig = {
  config+:: {
    local cfg = self,
    namespace: 'monitoring',
    version: 'v0.24.0',
    image: 'quay.io/thanos/thanos:' + cfg.version,
    imagePullPolicy: 'IfNotPresent',
    objectStorageConfig: {
      name: 'thanos-objstore-config',
      key: 'thanos.yaml',
    },
    hashringConfigMapName: 'hashring-config',
    volumeClaimTemplate: {
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '1Gi',
          },
        },
      },
    },
  },
};

local i = t.receiveIngestor(commonConfig.config {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
});

local r = t.receiveRouter(commonConfig.config {
  replicas: 1,
  replicaLabels: ['receive_replica'],
  replicationFactor: 1,
  endpoints: i.endpoints,
});

local s = t.store(commonConfig.config {
  replicas: 1,
  serviceMonitor: true,
});

local q = t.query(commonConfig.config {
  replicas: 1,
  replicaLabels: ['operator.prometheus.io/shard', 'prometheus_replica', 'rule_replica'],
  serviceMonitor: true,
  stores: [s.storeEndpoint, 'dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local:10901'] + i.storeEndpoints,
});

{ ['thanos-store-' + name]: s[name] for name in std.objectFields(s) } +
{ ['thanos-query-' + name]: q[name] for name in std.objectFields(q) } +
{ ['thanos-receive-router-' + resource]: r[resource] for resource in std.objectFields(r) } +
{ ['thanos-receive-ingestor-' + resource]: i[resource] for resource in std.objectFields(i) if resource != 'ingestors' } +
{
  ['thanos-receive-ingestor-' + hashring + '-' + resource]: i.ingestors[hashring][resource]
  for hashring in std.objectFields(i.ingestors)
  for resource in std.objectFields(i.ingestors[hashring])
  if i.ingestors[hashring][resource] != null
}

