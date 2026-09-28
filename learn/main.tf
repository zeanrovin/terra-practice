# ANATOMY: the main file. locals, resources, data sources and module calls.
# Work through the lessons in order. Each one has a matching output in
# outputs.tf, so `terraform apply` prints the result of every lesson.

# ---------------------------------------------------------------------------
# LESSON 1: locals. Named values you define once and reuse.
# var.  = came from outside (variables.tf)
# local. = defined right here
# ---------------------------------------------------------------------------
locals {
  name_prefix = "notes-${var.env}" # "notes-dev". ${...} builds a string
}

# ---------------------------------------------------------------------------
# LESSON 2: lists. An ordered set of values, written with [ ].
# ---------------------------------------------------------------------------
locals {
  service_names = keys(var.services)          # ["api", "web", "worker"] (sorted)
  first_service = local.service_names[0]      # "api". Lists are numbered from 0
  service_count = length(local.service_names) # 3
}

# ---------------------------------------------------------------------------
# LESSON 3: maps. Look up a value by its key, written with { }.
# ---------------------------------------------------------------------------
locals {
  api_settings = var.services["api"]        # api's whole settings object
  api_port     = var.services["api"].port   # 8080
  worker_cpu   = var.services["worker"].cpu # 512 (set explicitly)
  web_cpu      = var.services["web"].cpu    # 256 (filled in by optional())
}

# ---------------------------------------------------------------------------
# LESSON 4: for -> list. "Go through each item and give me ..."
#   [for ITEM in LIST : RESULT]
# ---------------------------------------------------------------------------
locals {
  upper_names = [for name in local.service_names : upper(name)] # ["API", "WEB", "WORKER"]
}

# ---------------------------------------------------------------------------
# LESSON 5: for -> map. Walk the services map, get a new map back.
#   {for KEY, VALUE in MAP : NEW_KEY => NEW_VALUE}
# ---------------------------------------------------------------------------
locals {
  ports = { for name, svc in var.services : name => svc.port }
  # { api = 8080, web = 80, worker = 0 }
}

# ---------------------------------------------------------------------------
# LESSON 6: for + if. Keep only some items (a filter).
# This is `web_services` in modules/services/main.tf.
# ---------------------------------------------------------------------------
locals {
  web_services = { for name, svc in var.services : name => svc if svc.port > 0 }
  # api and web only. worker has port 0, so it's dropped

  dynamodb_services = [for name, svc in var.services : name if svc.dynamodb_access]
  # ["api", "worker"]
}

# ---------------------------------------------------------------------------
# LESSON 7: conditional.  CONDITION ? VALUE_IF_TRUE : VALUE_IF_FALSE
# ---------------------------------------------------------------------------
locals {
  kinds = { for name, svc in var.services : name => svc.port > 0 ? "web-facing" : "background" }
  # { api = "web-facing", web = "web-facing", worker = "background" }
}

# ---------------------------------------------------------------------------
# LESSON 8: merge. Combine maps. Later maps win when keys clash.
# modules/services uses this for container environment variables.
# ---------------------------------------------------------------------------
locals {
  default_env = { TABLE_NAME = "${local.name_prefix}-notes", LOG_LEVEL = "info" }
  api_env     = merge(local.default_env, { LOG_LEVEL = "debug" })
  # { TABLE_NAME = "notes-dev-notes", LOG_LEVEL = "debug" }
}

# ---------------------------------------------------------------------------
# LESSON 9: for_each. `for` builds a VALUE, `for_each` builds RESOURCES.
# terraform_data is a built-in resource that stores a value and nothing else.
# It stands in for real AWS resources here, so this costs nothing.
#
# For each copy:  each.key   = "api" / "web" / "worker"
#                 each.value = that service's settings
# Addresses:      terraform_data.role["api"], terraform_data.role["web"], ...
# ---------------------------------------------------------------------------
resource "terraform_data" "role" {
  for_each = var.services

  input = {
    name = "${local.name_prefix}-${each.key}-task" # like aws_iam_role.task
    cpu  = each.value.cpu
  }
}

# ---------------------------------------------------------------------------
# LESSON 10: for_each over a filtered map + referencing another resource.
# Only api and worker get a "policy", like aws_iam_role_policy.dynamodb.
# terraform_data.role[each.key] = "the role with the same key as me".
# That reference is also how Terraform knows to create roles first.
# ---------------------------------------------------------------------------
resource "terraform_data" "dynamodb_policy" {
  for_each = { for name, svc in var.services : name => svc if svc.dynamodb_access }

  input = "allow DynamoDB for ${terraform_data.role[each.key].output.name}"
}

# ---------------------------------------------------------------------------
# LESSON 11: calling a module, once per service.
# A module is a folder of .tf files. You pass it inputs (its variables)
# and read its outputs as module.<name>.<output>.
# ---------------------------------------------------------------------------
module "label" {
  source   = "./modules/label"
  for_each = var.services

  name_prefix = local.name_prefix
  service     = each.key
  port        = each.value.port
}

# ---------------------------------------------------------------------------
# LESSON 12: reading the REAL inventory, exactly as terraform/dev does.
# ---------------------------------------------------------------------------
locals {
  real_services = yamldecode(file("${path.module}/../services.yaml"))
}

# ---------------------------------------------------------------------------
# EXERCISES. Change something, predict the plan, then run `terraform plan`.
#
# 1. Add a service:  cache = { port = 6379 }  to the default in variables.tf.
#    Which lessons' outputs change? How many resources are added?
# 2. Remove `dynamodb_access = true` from api. What gets destroyed?
# 3. Run: terraform apply -var env=prod
#    Why does every role get replaced, not updated in place?
# 4. Write a local that lists services with cpu > 256. Check it in
#    `terraform console` first.
# 5. Rename worker to jobs. Read the plan: why is it destroy + create
#    instead of a rename?
# ---------------------------------------------------------------------------
