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
{{- if .Values.image }}
          image: {{ .Values.registry }}/{{ .Values.org }}/{{ .Values.image }}:{{ .Values.tag }}
{{- else }}
          image: {{ .Values.registry }}/{{ .Values.org }}/vl3_ucnf-{{ .Values.nsm.serviceName }}:{{ .Values.tag }}
{{- end }}
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
            - name: IPAM_ADDRESS
              value: "ipam-{{ .Values.cnns.nsr.addr }}:50051"
            - name: NSE_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: NSM_REMOTE_NS_IP_LIST
              valueFrom:
                configMapKeyRef:
                  name: nsm-vl3-{{ .Values.nsm.serviceName }}
                  key: remote.ip_list
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
            privileged: true
          resources:
            limits:
              networkservicemesh.io/socket: 1
          volumeMounts:
            - mountPath: /etc/universal-cnf/config.yaml
              subPath: config.yaml
              name: universal-cnf-config-volume
      volumes:
        - name: universal-cnf-config-volume
          configMap:
            name: ucnf-vl3-{{ .Values.nsm.serviceName }}
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
      cnns:
        name: {{ .Values.cnns.nsr.name | quote }}
        address: {{ .Values.cnns.nsr.addr | quote }}
        connectivitydomain: {{ .Values.cnns.nsr.cd | quote}}
      vl3:
       ipam:
          prefixpool: {{ .Values.ipam.prefixPool | quote }}
          routes: []
       ifname: "endpoint0"
{{- if .Values.remote.ipList }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nsm-vl3-{{ .Values.nsm.serviceName }}
data:
  remote.ip_list: {{ .Values.remote.ipList | quote }}
{{- end }}

