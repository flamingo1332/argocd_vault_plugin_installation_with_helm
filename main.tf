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
