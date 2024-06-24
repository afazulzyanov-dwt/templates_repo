terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.22.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {
}

variable "customvar" {
  type = string
  default = ""
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
  default = "testprojecttf"
}

variable "customer" {
  type = string
  default = ""
}

data "external" "available_notebooks" {
  program = ["python", "/home/coder/notebooks.py"]
}

# data "coder_parameter" "notebook_id" {
#   name         = "notebook"
#   display_name = "notebook"
#   description  = "notebook"
#   icon         = "/icon/memory.svg"
#   mutable      = true
#   default = "unspecified"

#   option {
#     name  = "unspecified"
#     value = "unspecified"
#   }
#   dynamic "option" {
#     for_each = { for opt in jsondecode(data.external.available_notebooks.result["notebooks"]) : opt.name => opt.value }

#     content {
#       name  = option.key
#       value = option.value
#     }
#   }
# }

data "coder_parameter" "notebook_id" {
  name         = "notebook_id"
  display_name = "notebook_id"
  description  = "notebook_id"
  icon         = "/icon/memory.svg"
  mutable      = true
  type         = "string"
  default     = "nb"

  validation {
    regex = "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$"
    error = "The notebook ID must consist of alphanumeric characters and dashes only."
  }
}


data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 GB"
    value = "2"
  }
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

# data "coder_parameter" "home_disk_size" {
#   name         = "home_disk_size"
#   display_name = "Home disk size"
#   description  = "The size of the home disk in GB"
#   default      = "10"
#   type         = "number"
#   icon         = "/emojis/1f4be.png"
#   mutable      = false
#   validation {
#     min = 1
#     max = 99999
#   }
# }

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = <<-EOT
    set -e

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

# resource "kubernetes_persistent_volume_claim" "home" {
#   metadata {
#     name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}-home"
#     namespace = var.namespace
#     labels = {
#       "app.kubernetes.io/name"     = "coder-pvc"
#       "app.kubernetes.io/instance" = "coder-pvc-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
#       "app.kubernetes.io/part-of"  = "coder"
#       //Coder-specific labels.
#       "com.coder.resource"       = "true"
#       "com.coder.workspace.id"   = data.coder_workspace.me.id
#       "com.coder.workspace.name" = data.coder_workspace.me.name
#       "com.coder.user.id"        = data.coder_workspace.me.owner_id
#       "com.coder.user.username"  = data.coder_workspace.me.owner
#     }
#     annotations = {
#       "com.coder.user.email" = data.coder_workspace.me.owner_email
#     }
#   }
#   wait_until_bound = false
#   spec {
#     access_modes = ["ReadWriteOnce"]
#     resources {
#       requests = {
#         storage = "${data.coder_parameter.home_disk_size.value}Gi"
#       }
#     }
#   }
# }
data "kubernetes_secret" "secret_service" {
  metadata {
    name      = "secret-service"
    namespace = var.namespace
  }
}

data "kubernetes_secret" "secret_openai" {
  metadata {
    name      = "secret-openai"
    namespace = var.namespace
  }
}

data "kubernetes_secret" "secret_ji" {
  metadata {
    name      = "secret-ji"
    namespace = var.namespace
  }
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  # depends_on = [
  #   kubernetes_persistent_volume_claim.home
  # ]
  wait_for_rollout = false
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace.me.owner_id
      "com.coder.user.username"    = data.coder_workspace.me.owner
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace.me.owner_email
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "coder-workspace"
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "coder-workspace"
          "app" = "solara-${data.coder_parameter.notebook_id.value}"
        }
      }
      spec {
        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }

        image_pull_secrets {
          name = "regcred"
        }
        container {
          name              = "dev"
          image             = "goalprofit/solara:1.2"
          image_pull_policy = "Always"
          command           = ["sh", "-c", "bash /app/solara.sh\n${coder_agent.main.init_script}"]
          port {
            container_port = 8765
          }

          security_context {
            run_as_user = "1000"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "NOTEBOOK_ID"
            value = data.coder_parameter.notebook_id.value
          }
          env {
            name = "SERVICE_LOGIN"
            value = data.kubernetes_secret.secret_service.data["username"]
          }
          env {
            name = "SERVICE_PASSWORD"
            value = data.kubernetes_secret.secret_service.data["password"]
          }
          env {
            name = "OPENAI_API_KEY"
            value = data.kubernetes_secret.secret_openai.data["key"]
          }
          env {
            name = "JI_API_KEY"
            value = data.kubernetes_secret.secret_ji.data["key"]
          }
          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
          volume_mount {
            mount_path = "/notebooks"
            name       = "data"
            read_only  = true
          }
          volume_mount {
            mount_path = "/downloads"
            name       = "downloads"
          }
        }

        volume {
          name = "data"
          host_path {
            path = "/data/${var.customer}/data/jupyter/hub/common"
          }
        }
        volume {
          name = "downloads"
          host_path {
            path = "/data/${var.customer}/data/downloads"
          }
        }

        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
resource "kubernetes_service" "solara_notebook" {
  metadata {
    name = "solara-${data.coder_parameter.notebook_id.value}"
    namespace = var.namespace
  }
  spec {
    selector = {
      app = "solara-${data.coder_parameter.notebook_id.value}"
    }
    port {
      # name        = "http"
      port = 8765
      target_port = 8765
    }
    type = "ClusterIP"
  }
}
