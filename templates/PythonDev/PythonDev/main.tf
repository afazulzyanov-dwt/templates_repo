terraform {
  required_providers {
    coder = {
      source = "coder/coder"
      version = "=0.22.0"
    }
  }
}

provider "coder" {
}

data "local_file" "namespace" {
  filename   = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"
}

variable "customer" {
  type = string
  default = ""
}

variable "COOKIE_SESSION_NAME" {
  type = string
  default = ""
}

variable "CUSTOMER_VOLUME_CONFIG" {
  type = string
  default = ""
}

data "kubernetes_secret" "secret_service" {
  metadata {
    name      = "secret-service"
    namespace = local.namespace
  }
}

data "kubernetes_secret" "secret_openai" {
  metadata {
    name      = "secret-openai"
    namespace = local.namespace
  }
}


locals {
  work_image = "goalprofit/coder-python:1.0.0"
  namespace  = data.local_file.namespace.content
  customer_volume_config_parsed = try(jsondecode(var.CUSTOMER_VOLUME_CONFIG), {})
}

data "coder_parameter" "service_id" {
  name         = "service_id"
  display_name = "Service ID"
  description  = ""
  icon         = "/icon/python.svg"
  mutable      = true
  type         = "string"
  default     = "service-id"

  validation {
    regex = "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$"
    error = "The service ID must consist of alphanumeric characters and dashes only."
  }
  order = 10
}

data "coder_parameter" "mode" {
  name         = "mode"
  display_name = "Mode"
  icon         = "/icon/code.svg"
  mutable      = true
  default     = "debug"

  option {
    name  = "Production Mode"
    value = "production"
    description  = "In \"Production Mode\", the code is pulled from a Git repository using the \"Git Repository\" and \"Git Token\" parameters. Dependencies are installed from the \"requirements.txt\" file located at the root of the repository, if available. The service then starts automatically using the \"Run Command\" parameter, and code-server is not available. Authentication is handled via cookie."
  }

  option {
    name  = "Debug Mode"
    value = "debug"
    description  = "In \"Debug Mode\", the code is not pulled from the repository. Instead, a user-specific folder mounted from the host is used as the working directory. Dependencies are installed from the \"requirements.txt\" file in this folder, if available, and code-server is launched. Authentication uses data from the \"secret-service\" secret."
  }
  order = 12
}

data "coder_parameter" "run_command" {
  name         = "run_command"
  display_name = "Run Command"
  description  = "this parameter using in production mode to start service"
  icon         = "/icon/python.svg"
  mutable      = true
  type         = "string"
  default     = ""

  order = 13
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Provide the HTTPS URL of the Git repository"
  icon         = "/icon/git.svg"
  mutable      = true
  type         = "string"
  default      = ""
  order = 20
}

data "coder_parameter" "git_token" {
  name         = "git_token"
  display_name = "Git Token"
  description  = "Git token for authorization"
  icon         = "/icon/git.svg"
  mutable      = true
  type         = "string"
  default      = ""
  order = 30
}

data "coder_parameter" "git_tag" {
  name         = "git_tag"
  display_name = "Git Repository Tag"
  description  = "Git repository tag, or leave empty to pull the latest version"
  icon         = "/icon/git.svg"
  mutable      = true
  type         = "string"
  default      = ""
  order = 40
}


data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "1"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "1 Cores"
    value = "1"
  }
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  order = 50
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "1"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "1 GB"
    value = "1"
  }
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

  order = 60
}

# provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
#  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
# }

data "coder_workspace" "me" {}

locals {
  # code_server_start_command = data.coder_parameter.mode.value=="production" ? "" : join("\n", [
  #   "# install and start code-server",
  #   "curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0",
  #   "/tmp/code-server/bin/code-server --install-extension ms-python.python",
  #   "/tmp/code-server/bin/code-server --install-extension ms-pyright.pyright",
  #   "settings_file_path=~/.local/share/code-server/User/settings.json",
  #   "mkdir -p $(dirname \"$settings_file_path\")",
  #   "if [ ! -s \"$settings_file_path\" ]; then",
  #   "  echo {} > $settings_file_path",
  #   "fi",
  #   "jq '.[\"python.languageServer\"] = \"None\"' $settings_file_path > $settings_file_path.tmp && mv $settings_file_path.tmp $settings_file_path",
  #   "/tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &",
  # ])
  startup_script = data.coder_parameter.mode.value=="production" ? join("\n", [
    "git config --global user.name \"${data.coder_workspace.me.name}\"",
    "git config --global user.email ${data.coder_workspace.me.owner_email}",
    "mkdir -p /work/${data.coder_parameter.service_id.value}",
    "set -e",
    "sudo chown -R ubuntu:ubuntu /work",
    "cd /work/${data.coder_parameter.service_id.value}",
    "if [ -z \"$GIT_REPO\" ]; then",
    " echo [Git Repository] should be defined in Production Mode",
    " exit 1",
    "fi",
    "if [ -z \"$GIT_TOKEN\" ]; then",
    " echo [Git Token] should be defined in Production Mode",
    " exit 1",
    "fi",
    "REPO=$(echo $GIT_REPO | sed 's|https://||; s|.git$||')",
    "if [ -z \"$GIT_TAG\" ]; then",
    "git clone https://$GIT_TOKEN@$REPO ./",
    "else",
    "git clone --branch $GIT_TAG https://$GIT_TOKEN@$REPO ./",
    "fi",
    "if [ -f requirements.txt ]; then",
    "  pip install --no-cache-dir --upgrade pip",
    "  pip install --no-cache-dir -r requirements.txt",
    "fi",
    data.coder_parameter.run_command.value 
  ]): join("\n", [
    "git config --global user.name \"${data.coder_workspace.me.name}\"",
    "git config --global user.email ${data.coder_workspace.me.owner_email}",
    "set -e",
    "mkdir -p /work/${data.coder_parameter.service_id.value}",
    "sudo chown -R ubuntu:ubuntu /work",
    "cd /work/${data.coder_parameter.service_id.value}",
    "# install and start code-server",
    "curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0",
    "/tmp/code-server/bin/code-server --install-extension ms-python.python",
    "/tmp/code-server/bin/code-server --install-extension ms-pyright.pyright",
    "settings_file_path=~/.local/share/code-server/User/settings.json",
    "mkdir -p $(dirname \"$settings_file_path\")",
    "if [ ! -s \"$settings_file_path\" ]; then",
    "  echo {} > $settings_file_path",
    "fi",
    "jq '.[\"python.languageServer\"] = \"None\"' $settings_file_path > $settings_file_path.tmp && mv $settings_file_path.tmp $settings_file_path",
    "/tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &",
    "if [ -f requirements.txt ]; then",
    "  pip install --no-cache-dir --upgrade pip",
    "  pip install --no-cache-dir -r requirements.txt",
    "fi",
  ])
  app_agent_id_for_code_server = data.coder_parameter.mode.value=="production" ? 0 : coder_agent.main.id
#locals {
  #python_requirements_install = data.coder_parameter.python_requirements.value == "" ? "echo no requirements" : "pip install ${data.coder_parameter.python_requirements.value}"
#}
}
resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  display_apps {
    port_forwarding_helper = false
    ssh_helper = false
    vscode = false
    vscode_insiders = false
    web_terminal = true
  }
  startup_script = local.startup_script
  # startup_script = <<-EOT
  #   set -e

  #   # install and start code-server
  #   curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.11.0
  #   /tmp/code-server/bin/code-server --install-extension ms-python.python
  #   /tmp/code-server/bin/code-server --install-extension ms-pyright.pyright
  #   settings_file_path=~/.local/share/code-server/User/settings.json
  #   mkdir -p $(dirname "$settings_file_path")
  #   if [ ! -s "$settings_file_path" ]; then
  #     echo {} > $settings_file_path
  #   fi
  #   jq '.["python.languageServer"] = "None"' $settings_file_path > $settings_file_path.tmp && mv $settings_file_path.tmp $settings_file_path
  #   ${local.python_requirements_install}
  #   sudo chown -R ubuntu:ubuntu /work
  #   %{ if data.coder_parameter.production_mode == false }
  #   /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  #   %{ endif }    
  # EOT


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
    display_name = "Work Disk"
    key          = "3_work_disk"
    script       = "coder stat disk --path /work"
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
  agent_id     = local.app_agent_id_for_code_server
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/work/${data.coder_parameter.service_id.value}"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}


resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count

  wait_for_rollout = false
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = local.namespace
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
          "app" = "pyservice-${data.coder_parameter.service_id.value}"
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
          name              = "${data.coder_parameter.service_id.value}"
          image             = local.work_image
          image_pull_policy = "Always"
          env {
            name = "CODER_AGENT_URL"
            value = "http://coder"
          }
          # command           = ["sh", "-c", "bash /app/solara.sh\n${coder_agent.main.init_script}"]
          command           = ["sh", "-c", "bash ${coder_agent.main.init_script}"]
          working_dir = "/work/${data.coder_parameter.service_id.value}"

          port {
            container_port = 8080
          }

          security_context {
            run_as_user = "1000"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "COOKIE_SESSION_NAME"
            value = var.COOKIE_SESSION_NAME
          }
          env {
            name  = "CUSTOMER_VOLUME_CONFIG"
            value = var.CUSTOMER_VOLUME_CONFIG
          }
          env {
            name = "PYTHON_SERVER_ROOT_URL"
            value = "/pyservice/${data.coder_parameter.service_id.value}/"
          }
          env {
            name = "SERVICE_LOGIN"
            value_from {
              secret_key_ref {
                name = "secret-service"
                key  = "username"
              }
            }
          }          
          env {
            name = "SERVICE_PASSWORD"
            value_from {
              secret_key_ref {
                name = "secret-service"
                key  = "password"
              }
            }
          }
          # env {
          #   name = "SERVICE_LOGIN"
          #   value = data.kubernetes_secret.secret_service.data["username"]
          # }
          # env {
          #   name = "SERVICE_PASSWORD"
          #   value = data.kubernetes_secret.secret_service.data["password"]
          # }
          env {
            name = "OPENAI_API_KEY"
            value = data.kubernetes_secret.secret_openai.data["key"]
          }
          env {
           name  = "GIT_REPO"
           value = data.coder_parameter.git_repo.value
          }
          env {
           name  = "GIT_TOKEN"
           value = data.coder_parameter.git_token.value
          }
          env {
           name  = "GIT_TAG"
           value = data.coder_parameter.git_tag.value
          }

          #env {
          #  name = "DATASCIENCE_VAULT_URL"
          #  value = data.kubernetes_secret.data_science_vault.data["dataScienceVaultUrl"]
          #}
          #env {
          #  name = "DATASCIENCE_VAULT_CLIENT_ID"
          #  value = data.kubernetes_secret.data_science_vault.data["dataScienceVaultClientId"]
          #}
          resources {
            requests = {
              "cpu"    = "0m"
              "memory" = "1Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
          dynamic "volume_mount" {
            for_each = data.coder_parameter.mode.value == "debug" ? [1] : []

            content {
              mount_path = "/work"
              name       = "customer"
              sub_path   = "data/coder/pythondev/${lower(data.coder_workspace.me.owner)}"
            }
          }          
          # volume_mount {
          #   mount_path = "/work"
          #   name       = "customer"
          #   sub_path = "data/coder/pythondev/${lower(data.coder_workspace.me.owner)}"
          # }
        }


        volume {
          name = "customer"

          dynamic "host_path" {
            for_each = lookup(local.customer_volume_config_parsed, "hostPath", null) != null ? [local.customer_volume_config_parsed.hostPath] : []
            content {
              path = host_path.value.path
              type = host_path.value.type
            }
          }
          dynamic "persistent_volume_claim" {
            for_each = lookup(local.customer_volume_config_parsed, "persistentVolumeClaim", null) != null ? [local.customer_volume_config_parsed.persistentVolumeClaim] : []
            content {
              claim_name = persistent_volume_claim.value.claimName
            }
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
resource "kubernetes_service" "pyservice" {
  metadata {
    name = "pyservice-${data.coder_parameter.service_id.value}"
    namespace = local.namespace
  }
  spec {
    selector = {
      app = "pyservice-${data.coder_parameter.service_id.value}"
    }
    port {
      # name        = "http"
      port = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}