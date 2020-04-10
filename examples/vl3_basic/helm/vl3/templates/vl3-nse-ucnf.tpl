---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vl3-nse-{{ .Values.nsm.serviceName }}
  namespace: {{ .Release.Namespace }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      networkservicemesh.io/app: "vl3-nse-{{ .Values.nsm.serviceName }}"
      networkservicemesh.io/impl: {{ .Values.nsm.serviceName | quote }}
  template:
    metadata:
      labels:
        networkservicemesh.io/app: "vl3-nse-{{ .Values.nsm.serviceName }}"
        networkservicemesh.io/impl: {{ .Values.nsm.serviceName | quote }}
        cnns/nse.servicename: {{ .Values.nsm.serviceName | quote }}
      annotations:
        sidecar.istio.io/inject: "false"
{{- if .Values.cnns.nsr.addr }}
        cnns/nsr.address: {{ .Values.cnns.nsr.addr | quote }}
        cnns/nsr.port: {{ .Values.cnns.nsr.port | quote }}
{{- end }}
    spec:
      containers:
        - name: vl3-nse
          image: {{ .Values.registry }}/{{ .Values.org }}/vl3_ucnf-vl3-nse:{{ .Values.tag }}
          imagePullPolicy: {{ .Values.pullPolicy }}
          env:
            - name: ADVERTISE_NSE_NAME
              value: {{ .Values.nsm.serviceName | quote }}
            - name: ADVERTISE_NSE_LABELS
              value: "app=vl3-nse-{{ .Values.nsm.serviceName }}"
            - name: TRACER_ENABLED
              value: "true"
            - name: JAEGER_SERVICE_HOST
              value: jaeger.nsm-system
            - name: JAEGER_SERVICE_PORT_JAEGER
              value: "6831"
            - name: JAEGER_AGENT_HOST
              value: jaeger.nsm-system
            - name: JAEGER_AGENT_PORT
              value: "6831"
            - name: NSREGISTRY_ADDR
              value: "nsmgr.nsm-system"
            - name: NSREGISTRY_PORT
              value: "5000"
            - name: NSE_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
{{- if .Values.ipam.uniqueOctet }}
            - name: NSE_IPAM_UNIQUE_OCTET
              value: {{ .Values.ipam.uniqueOctet | quote }}
{{- end }}
            - name: NSM_REMOTE_NS_IP_LIST
              valueFrom:
                configMapKeyRef:
                  name: nsm-vl3-{{ .Values.nsm.serviceName }}
                  key: remote.ip_list
            - name: MICROSERVICE_LABEL
              value: {{ .Values.aio.serviceLabel }}
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
            privileged: true
          ports:
            - containerPort: 9111
            - containerPort: 9191
          {{- if .Values.probes.enabled }}
          readinessProbe:
            httpGet:
              path: /readiness
              port: 9191
              {{- if .Values.aio.http.secureTransport }}
              scheme: HTTPS
              httpHeaders:
                - name: Authorization
                  value: "Basic {{ .Values.aio.http.secrets.basicAuth | b64enc }}"
              {{- end }}
            periodSeconds: {{ .Values.probes.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.failureThreshold }}
            initialDelaySeconds: {{ .Values.probes.readinessInitialDelaySeconds }}
          livenessProbe:
            httpGet:
              path: /liveness
              port: 9191
              {{- if .Values.aio.http.secureTransport }}
              scheme: HTTPS
              httpHeaders:
                - name: Authorization
                  value: "Basic {{ .Values.aio.http.secrets.basicAuth | b64enc }}"
              {{- end }}
            periodSeconds: {{ .Values.probes.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.failureThreshold }}
            initialDelaySeconds: {{ .Values.probes.livenessInitialDelaySeconds }}
          {{- end }}
          resources:
            limits:
              networkservicemesh.io/socket: 1
            {{- if .Values.aio.hugePages.enabled }}
              hugepages-2Mi: {{ .Values.aio.hugePages.size }}
              memory: {{ .Values.aio.hugePages.size }}
            {{- end }}
          volumeMounts:
            - mountPath: /etc/universal-cnf/config.yaml
              subPath: config.yaml
              name: universal-cnf-config-volume
            - name: agent-config
              mountPath: /opt/aio-agent/dev
            - name: kiknosctl-config
              mountPath: /root/.agentctl/
            - name: memif-sockets
              mountPath: {{ .Values.vswitch.memifSocketDir }}
            - name: vpp-config
              mountPath: /etc/vpp/vpp.conf
              subPath: vpp.conf
            - name: strongswan-config
              mountPath: /etc/strongswan.conf
              subPath: strongswan.conf
            - name: strongswan-vpp-config
              mountPath: /etc/strongswan.d/charon/kernel-vpp.conf
              subPath: kernel-vpp.conf
            {{- if .Values.etcd.secureTransport }}
            - name: etcd-secrets
              mountPath: /var/etcd/secrets
            {{- end }}
            {{- if .Values.aio.http.secureTransport }}
            - name: http-secrets
              mountPath: /var/http/secrets
            {{- end }}
            {{- if .Values.strongswan.secrets.encryption.enabled }}
            - name: strongswan-secrets
              mountPath: /var/strongswan/secrets
            {{- end }}
      volumes:
        - name: universal-cnf-config-volume
          configMap:
            name: ucnf-vl3-{{ .Values.nsm.serviceName }}
        - name: agent-config
          configMap:
            name: aio-agent-cfg
        - name: kiknosctl-config
          configMap:
            name: aio-kiknosctl-cfg
        - name: memif-sockets
          hostPath:
            path: {{ .Values.vswitch.memifSocketDir }}
        - name: vpp-config
          configMap:
            name: kiknos-vpp-cfg
        - name: strongswan-config
          configMap:
            name: strongswan-cfg
        - name: strongswan-vpp-config
          configMap:
            name: strongswan-vpp-cfg
        {{- if .Values.etcd.secureTransport }}
        - name: etcd-secrets
          secret:
            secretName: {{ .Values.etcd.secrets.secretName }}
        {{- end }}
        {{- if .Values.aio.http.secureTransport }}
        - name: http-secrets
          secret:
            secretName: {{ .Values.aio.http.secrets.secretName }}
        {{- end }}
        {{- if .Values.strongswan.secrets.encryption.enabled }}
        - name: strongswan-secrets
          secret:
            secretName: {{ .Values.strongswan.secrets.encryption.keysSecretName }}
        {{- end }}

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ucnf-vl3-{{ .Values.nsm.serviceName }}
data:
  config.yaml: |
    endpoints:
    - name: {{ .Values.nsm.serviceName | quote }}
      labels:
        app: "vl3-nse-{{ .Values.nsm.serviceName }}"
{{- if .Values.cnns.nsr.addr }}
        cnns/nsr.addr: {{ .Values.cnns.nsr.addr | quote }}
        cnns/nsr.port: {{ .Values.cnns.nsr.port | quote }}
{{- end }}
      ipam:
        prefixpool: {{ .Values.ipam.prefixPool | quote }}
        routes: []
      ifname: "endpoint0"

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: aio-agent-cfg
data:
  vpp-ifplugin.conf: |
    #publish-statistics: [etcd]
  {{- if not .Values.aio.logs.txnSummary }}
  kvscheduler.conf: |
    print-txn-summary: false
  {{- end }}
  etcd.conf: |
    endpoints:
      {{- if .Values.etcd.useExternalEtcd }}
      - "{{ .Values.etcd.externalEtcdEndpoint }}"
      {{- else }}
      - {{ .Values.etcd.serviceName }}:2379
      {{- end }}
    {{- if .Values.etcd.secureTransport }}
    insecure-transport: false
    cert-file: /var/etcd/secrets/{{ .Values.etcd.secrets.clientCertFile }}
    key-file: /var/etcd/secrets/{{ .Values.etcd.secrets.clientKeyFile }}
    ca-file: /var/etcd/secrets/{{ .Values.etcd.secrets.caCertFile }}
    {{- else }}
    insecure-transport: true
    {{- end }}
    dial-timeout: 10000000000
    allow-delayed-start: true
  grpc-sswan.conf: |
    endpoint: /run/vpp-agent.sock
    network: unix
    permission: 700
    max-msg-size: 4096
  grpc.conf: |
    endpoint: 0.0.0.0:9111
    {{- if .Values.aio.http.secureTransport }}
    insecure-transport: false
    cert-file: /var/http/secrets/{{ .Values.aio.http.secrets.serverCertFile }}
    key-file: /var/http/secrets/{{ .Values.aio.http.secrets.serverKeyFile }}
    ca-files:
      - /var/http/secrets/{{ .Values.aio.http.secrets.caCertFile }}
    {{- else }}
    insecure-transport: true
    {{- end }}
    network: tcp
    max-msg-size: 4096
  http.conf: |
    endpoint: 0.0.0.0:9191
    {{- if .Values.aio.http.secureTransport }}
    server-cert-file: /var/http/secrets/{{ .Values.aio.http.secrets.serverCertFile }}
    server-key-file: /var/http/secrets/{{ .Values.aio.http.secrets.serverKeyFile }}
    client-basic-auth:
      - {{ .Values.aio.http.secrets.basicAuth | quote }}
    {{- end }}
  {{- if .Values.strongswan.secrets.encryption.enabled }}
  kiknos.conf: |
    KiknosConfig:
      secretsKeyFile: /var/strongswan/secrets/{{ .Values.strongswan.secrets.encryption.privateKeyFile }}
  {{- end }}
  supervisor.conf: |
    programs:
      - name: "vpp"
        executable-path: "/usr/bin/vpp"
        executable-args: ["-c", "/etc/vpp/vpp.conf"]
      - name: "aio-agent"
        executable-path: "/usr/bin/aio-agent"
        executable-args: ["--config-dir=/opt/aio-agent/dev"]
      - name: "strongswan"
        executable-path: "/usr/local/libexec/ipsec/charon"
        executable-args: ["--use-syslog"]
    hooks:
      - cmd: "/usr/bin/init_hook.sh"

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: aio-kiknosctl-cfg
data:
  config.yml: |
    etcd-endpoints:
    {{- if .Values.etcd.useExternalEtcd }}
      - "{{ .Values.etcd.externalEtcdEndpoint }}"
    {{- else }}
      - {{ .Values.etcd.serviceName }}:2379
    {{- end }}
    etcd-dial-timeout: 20000000000
    {{- if .Values.etcd.secureTransport }}
    kvdb-tls:
      cert-file: /var/etcd/secrets/{{ .Values.etcd.secrets.clientCertFile }}
      key-file: /var/etcd/secrets/{{ .Values.etcd.secrets.clientKeyFile }}
      ca-file: /var/etcd/secrets/{{ .Values.etcd.secrets.caCertFile }}
    {{- end }}
    {{- if .Values.aio.http.secureTransport }}
    http-tls:
      ca-file: /var/http/secrets/{{ .Values.aio.http.secrets.caCertFile }}
    http-basic-auth: {{ .Values.aio.http.secrets.basicAuth | quote }}
    grpc-tls:
      cert-file: /var/http/secrets/{{ .Values.aio.http.secrets.clientCertFile }}
      key-file: /var/http/secrets/{{ .Values.aio.http.secrets.clientKeyFile }}
      ca-file: /var/http/secrets/{{ .Values.aio.http.secrets.caCertFile }}
    {{- end }}

{{- if and .Values.aio.http.secureTransport .Values.aio.http.secrets.loadFromFiles }}
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: {{ .Values.aio.http.secrets.secretName }}
data:
  {{ .Values.aio.http.secrets.caCertFile }}: |-
    {{ .Files.Get (printf "secrets/%s" .Values.aio.http.secrets.caCertFile) | b64enc }}
  {{ .Values.aio.http.secrets.serverCertFile }}: |-
    {{ .Files.Get (printf "secrets/%s" .Values.aio.http.secrets.serverCertFile) | b64enc }}
  {{ .Values.aio.http.secrets.serverKeyFile }}: |-
    {{ .Files.Get (printf "secrets/%s" .Values.aio.http.secrets.serverKeyFile) | b64enc }}
  {{ .Values.aio.http.secrets.clientCertFile }}: |-
    {{ .Files.Get (printf "secrets/%s" .Values.aio.http.secrets.clientCertFile) | b64enc }}
  {{ .Values.aio.http.secrets.clientKeyFile }}: |-
    {{ .Files.Get (printf "secrets/%s" .Values.aio.http.secrets.clientKeyFile) | b64enc }}
{{- end }}
