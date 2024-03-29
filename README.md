# Argo CD Vault Plugin Installation Guide with Helm

This repository provides a simple guide to installing the Argo CD Vault Plugin using Helm and Terraform using sidecar option.  You can easily install argocd-vault-plugin (sidecar installation option) just by changing the parameters of the argocd helm chart.

## Prerequisites
- k8s Cluster
- Helm
- Terraform (if using the Terraform method)


### values.yaml
configs.cmp.create: true -> configmap with name argocd-cmp-cm will be created. This configmap is mounted to sidecar container.

configuration such as AVP_TYPE, TOKEN is passed to sidecar container  as environment variables.

```
configs:
  cmp:
    create: true
    plugins:
      avp-helm:
        allowConcurrency: true
        discover:
          find:
            command:
              - sh
              - "-c"
              - "find . -name 'Chart.yaml' && find . -name 'values.yaml'"
        generate:
          command:
            - bash
            - "-c"
            - |
              helm template $ARGOCD_APP_NAME -n $ARGOCD_APP_NAMESPACE -f <(echo "$ARGOCD_ENV_HELM_VALUES") . |
              argocd-vault-plugin generate -
        lockRepo: false

      avp-kustomize:
        allowConcurrency: true
        discover:
          find:
            command:
              - find
              - "."
              - -name
              - kustomization.yaml
        generate:
          command:
            - sh
            - "-c"
            - "kustomize build . | argocd-vault-plugin generate -"
        lockRepo: false
      
      avp:
        allowConcurrency: true
        discover:
          find:
            command:
              - sh
              - "-c"
              - "find . -name '*.yaml' | xargs -I {} grep \"<path\\|avp\\.kubernetes\\.io\" {} | grep ."
        generate:
          command:
            - argocd-vault-plugin
            - generate
            - "."
        lockRepo: false


repoServer:
  volumes:
    - configMap:
        name: argocd-cmp-cm
      name: argocd-cmp-cm
    - name: custom-tools
      emptyDir: {}
    
  initContainers:
    - name: download-tools
      image: registry.access.redhat.com/ubi8
      env:
        - name: AVP_VERSION
          value: "1.17.0"
      command: ["sh", "-c"]
      args:
        - >-
          curl -L https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.17.0/argocd-vault-plugin_1.17.0_linux_amd64 -o argocd-vault-plugin &&
          chmod +x argocd-vault-plugin &&
          mv argocd-vault-plugin /custom-tools/
      volumeMounts:
        - name: custom-tools
          mountPath: /custom-tools


  extraContainers:
  # argocd-vault-plugin with Helm
  - name: avp-helm
    command: [/var/run/argocd/argocd-cmp-server]
    image: quay.io/argoproj/argocd:v2.10.1
    env:
    # configuration  https://argocd-vault-plugin.readthedocs.io/en/stable/config/#environment-variables
    - name: AVP_TYPE
      value: awssecretsmanager
    - name: AWS_REGION
      value: ap-northeast-1
    - name: AWS_ACCESS_KEY_ID
      value: "XXXXXXXXXXXXXXXXXXXXX"
    - name: AWS_SECRET_ACCESS_KEY
      value: "XXXXXXXXXXXXXXXXXXXXX"  
    securityContext:
      runAsNonRoot: true
      runAsUser: 999
    volumeMounts:
      - mountPath: /var/run/argocd
        name: var-files
      - mountPath: /home/argocd/cmp-server/plugins
        name: plugins
      - mountPath: /tmp
        name: tmp
      - mountPath: /home/argocd/cmp-server/config/plugin.yaml
        subPath: avp-helm.yaml
        name: argocd-cmp-cm
      - name: custom-tools
        subPath: argocd-vault-plugin
        mountPath: /usr/local/bin/argocd-vault-plugin 
  
  # argocd-vault-plugin with kustomize
  - name: avp-kustomize
    command: [/var/run/argocd/argocd-cmp-server]
    image: quay.io/argoproj/argocd:v2.10.1
    env:
    securityContext:
      runAsNonRoot: true
      runAsUser: 999
    volumeMounts:
      - mountPath: /var/run/argocd
        name: var-files
      - mountPath: /home/argocd/cmp-server/plugins
        name: plugins
      - mountPath: /tmp
        name: tmp
      - mountPath: /home/argocd/cmp-server/config/plugin.yaml
        subPath: avp-kustomize.yaml
        name: argocd-cmp-cm
      - name: custom-tools
        subPath: argocd-vault-plugin
        mountPath: /usr/local/bin/argocd-vault-plugin

  # argocd-vault-plugin with plain YAML
  - name: avp
    command: [/var/run/argocd/argocd-cmp-server]
    image: quay.io/argoproj/argocd:v2.10.1
    securityContext:
      runAsNonRoot: true
      runAsUser: 999
    volumeMounts:
      - mountPath: /var/run/argocd
        name: var-files
      - mountPath: /home/argocd/cmp-server/plugins
        name: plugins
      - mountPath: /tmp
        name: tmp
      - mountPath: /home/argocd/cmp-server/config/plugin.yaml
        subPath: avp.yaml
        name: argocd-cmp-cm
      - name: custom-tools
        subPath: argocd-vault-plugin
        mountPath: /usr/local/bin/argocd-vault-plugin



```

&nbsp;
### Installation with Terraform, helm terraform provider(avp-helm)
```
locals {
  cluster_endpoint = ""
  cluster_ca_cert  = ""
  cluster_name     = ""

  avp_version      = "1.17.0"
  argocd_version   = "2.10.1"
}

variable "aws_region" {
  type = string
  default = "us-west-1"
}
variable "AWS_ACCESS_KEY_ID" {
  type = string
  default = "xxxxxxxxx"
}
variable "AWS_SECRET_ACCESS_KEY" {
  type = string
  default = "xxxxxxxxx"
}

provider "helm" {
  # kubernetes {
  #   host                   = local.cluster_endpoint
  #   cluster_ca_certificate = base64decode(local.cluster_ca_cert)
  #   exec {
  #     api_version = "client.authentication.k8s.io/v1beta1"
  #     args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  #     command     = "aws"
  #   }
  # }

  kubernetes {
    config_path = "/home/user/.kube/config" # Path to your local kubectl config file
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "6.0.3"

  create_namespace = true

  values = [
    <<-EOT
    configs:
      cmp:
        create: true
        plugins:
          avp-helm:
            allowConcurrency: true
            discover:
              find:
                command:
                  - sh
                  - "-c"
                  - "find . -name 'Chart.yaml' && find . -name 'values.yaml'"
            generate:
              command:
                - bash
                - "-c"
                - |
                  helm template $ARGOCD_APP_NAME -n $ARGOCD_APP_NAMESPACE -f <(echo "$ARGOCD_ENV_HELM_VALUES") . |
                  argocd-vault-plugin generate -
            lockRepo: false

    repoServer:
      volumes:
        - configMap:
            name: argocd-cmp-cm
          name: argocd-cmp-cm
        - name: custom-tools
          emptyDir: {}
    
      initContainers:
        - name: download-tools
          image: registry.access.redhat.com/ubi8
          env:
            - name: AVP_VERSION
              value: ${local.avp_version}
          command: ["sh", "-c"]
          args:
            - >-
              curl -L https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v${local.avp_version}/argocd-vault-plugin_${local.avp_version}_linux_amd64 -o argocd-vault-plugin &&
              chmod +x argocd-vault-plugin &&
              mv argocd-vault-plugin /custom-tools/
          volumeMounts:
            - name: custom-tools
              mountPath: /custom-tools


      extraContainers:
      - name: avp-helm
        command: [/var/run/argocd/argocd-cmp-server]
        image: quay.io/argoproj/argocd:v${local.argocd_version}
        
        # configuration  https://argocd-vault-plugin.readthedocs.io/en/stable/config/#environment-variables
        env:
        - name: AVP_TYPE
          value: awssecretsmanager
        - name: AWS_REGION
          value: ${var.aws_region}
        - name: AWS_ACCESS_KEY_ID
          value: ${var.AWS_ACCESS_KEY_ID}
        - name: AWS_SECRET_ACCESS_KEY
          value: ${var.AWS_SECRET_ACCESS_KEY}
        securityContext:
          runAsNonRoot: true
          runAsUser: 999
        volumeMounts:
          - mountPath: /var/run/argocd
            name: var-files
          - mountPath: /home/argocd/cmp-server/plugins
            name: plugins
          - mountPath: /tmp
            name: tmp
          - mountPath: /home/argocd/cmp-server/config/plugin.yaml
            subPath: avp-helm.yaml
            name: argocd-cmp-cm
          - name: custom-tools
            subPath: argocd-vault-plugin
            mountPath: /usr/local/bin/argocd-vault-plugin 

    EOT
  ]
}

```

Credentials can be stored in terraform cloud or github actions secret and then injected into the sidecar container.




&nbsp;
### Application manifest example(avp-helm)
```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: wordpress
  namespace: argocd
  annotations:
spec:
  project: default
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: wordpress
  source:
    repoURL: 'https://charts.bitnami.com/bitnami'
    chart: wordpress
    targetRevision: '19.0.4' 
    plugin:
      env:
        - name: HELM_VALUES
          value: |
            wordpressUsername: user
            wordpressEmail: values@example.com
            wordpressBlogName: MyBlog
            wordpressPassword: <path:path/to/secret#key>

```
You can inject the secret directly into the Argocd application manifest from AVP_TYPE that you specified when installing argocd vault plugin.
