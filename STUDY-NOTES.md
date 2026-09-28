# Study notes: Terraform + AWS (Sunday session, 2026-09-27)

What we covered while deploying the notes app with plain Terraform (`terraform/dev/`).

## Where things stand

| Item | Status |
|---|---|
| State bucket `terra-practice-tfstate-194169209897` (`bootstrap/`) | Created. Keep it until you're completely done (costs well under a cent a month) |
| Dev stack (`terraform/dev/`) | **Destroyed** (46 resources, confirmed empty in AWS). Nothing is billing. Notes and ECR images were deleted with it |
| App URL | None while destroyed. A redeploy gets a **new** URL: `terraform output app_url` |
| Exercise 1 (console tour) | Instructions given |
| Exercise 2 (add `docs` service) | Code committed, **not deployed yet**. Resuming (below) deploys it |
| Exercises 3–6 | Not started |
| `learn/` practice project | Created, costs nothing |
| AWS account / region | `194169209897` / `us-west-2` (Oregon) |

### Resuming after a break

```bash
cd ~/git/terra-practice/terraform/dev
terraform apply -target=module.ecr     # repos first (now 4, including docs)
../../scripts/push-images.sh v1        # rebuild + push all images (Docker Desktop must be running)
terraform apply                        # everything else, ~5 min, starts billing (~$0.13/hr)
terraform output app_url               # new URL; give it 1–2 min for health checks
```

Pausing again: `terraform destroy` in `terraform/dev` (keep `bootstrap/`).

---

## 1. What we ran

```bash
# State bucket (once). Uses LOCAL state because the bucket can't store its own state
cd bootstrap && terraform init && terraform apply

# Main stack
cd terraform/dev
terraform init -backend-config=backend.hcl   # connect to the S3 state bucket
terraform validate
terraform plan                               # 46 to add
terraform apply -target=module.ecr           # ECR first: images must exist before services start
../../scripts/push-images.sh v1              # build + push web, api, worker
terraform apply                              # the remaining 40
```

`plan` creates nothing and writes no state. The state file appears in S3 on the first `apply`.

## 2. The bug we hit (and the debugging path)

**Symptom:** `api` and `worker` deployments `FAILED`, `web` returned 403.

**How we found it:**
1. `aws ecs describe-services`: running count 0, rollout `FAILED` (circuit breaker gave up)
2. Stopped task reason: `Essential container in task exited`, exit code 2
3. CloudWatch Logs `/ecs/notes-dev/<svc>`: `Permission denied` opening `app.py` / `index.html`

**Cause:** the source files were `-rw-------` (owner only). Docker `COPY` keeps that mode and makes root the owner, so `USER nobody` (api, worker) and nginx (web) couldn't read them.

**Fix:** `COPY --chmod=644 ...` in all three Dockerfiles, re-pushed `v1`, then
`aws ecs update-service --force-new-deployment`. No Terraform change was needed because the task definitions still point at `:v1`.

**Lesson:** when something doesn't start, check the stop reason first, then CloudWatch Logs.

---

## 3. How the app runs on AWS

Three places:

| What | Where it lives |
|---|---|
| **Code** | `apps/<svc>/` → built into a Docker image → stored in **ECR** (`notes-dev/<svc>:v1`). AWS never sees the Git repo |
| **Config** | The ECS **task definition**, built by Terraform from `services.yaml` + module outputs (e.g. `TABLE_NAME=notes-dev-notes`, image tag) |
| **Infrastructure** | Everything in `modules/`, wired together by `terraform/dev/main.tf` |

The code has no AWS credentials. boto3 gets temporary credentials from the **task role**.

```
You → ALB (public subnets, :80)
        ├─ /api/* (priority 100) → api  :8080 ─┐
        ├─ /docs* (priority 150) → docs :80    │   (after Exercise 2)
        └─ /*     (priority 200) → web  :80    │
                                               ▼
               worker (no port, no ALB) ──→ DynamoDB  notes-dev-notes
```

### The three images

| Image | Built from | What it is | Port | Talks to |
|---|---|---|---|---|
| **web** | `apps/web/` | nginx serving one HTML page | 80 | Nothing. Your browser runs its JavaScript, which calls `/api/...` |
| **api** | `apps/api/app.py` | Python HTTP server | 8080 | DynamoDB (read/write notes) |
| **worker** | `apps/worker/worker.py` | Python loop | none | DynamoDB (heartbeat every 60s) |

Usual real-world split: **web** = what users see, **api** = logic and data access, **worker** = background jobs nobody waits on.

---

## 4. AWS concepts

### VPC and subnets

- **VPC** = your private network (`10.0.0.0/16`). Nothing gets in or out without a gateway.
- **Subnets** = slices of it, each in one availability zone (a separate data center). Two AZs so one can fail, and the ALB requires two.
- **Public or private is decided by the route table:**
  - Public: `0.0.0.0/0 → internet gateway`: traffic both ways. The ALB lives here.
  - Private: `0.0.0.0/0 → NAT gateway`: outbound only. Containers live here.
- **Security groups** = a firewall per resource. `notes-dev-alb` allows :80 from anywhere. `notes-dev-tasks` allows traffic **only from the ALB's security group**.

```
VPC 10.0.0.0/16
├── us-west-2a: public 10.0.0.0/24 (ALB, NAT)   private 10.0.10.0/24 (containers)
└── us-west-2b: public 10.0.1.0/24 (ALB)        private 10.0.11.0/24 (containers)
```

### ECR vs ECS vs Fargate

| Service | Role |
|---|---|
| **ECR** | **Stores** images (a private Docker Hub). One repo per app, many tags per repo |
| **ECS** | **Decides what runs**: which image, how many copies, restarts on crash |
| **Fargate** | **The machines**, managed by AWS, never seen |

ECS terms:
- **Cluster**: a grouping (`notes-dev`)
- **Task definition**: the recipe (image, CPU/memory, env vars, roles), roughly `docker run` written down. Can't be edited; every change is a new **revision**.
- **Task**: one running container
- **Service**: keeps N tasks running and connects them to the ALB target group
- **Circuit breaker**: stops retrying after repeated crashes and rolls back

### ALB (Application Load Balancer)

Listener (:80, default 404) → **rules** checked lowest priority number first → **target group** → container IPs, which it health-checks.

### Two IAM roles (easy to mix up)

| Role | Used by | For |
|---|---|---|
| **Execution role** `notes-dev-ecs-execution` | ECS itself | Pull the image from ECR, write logs to CloudWatch |
| **Task role** `notes-dev-<svc>-task` | **Your code** | Call AWS. Only api and worker get DynamoDB access |

### DynamoDB

- No separate "database" or server. The **table** is the top-level thing.
- Key-value (NoSQL): every item needs a key (`pk`, e.g. `note#<uuid>`, `heartbeat#worker`), and other fields can vary. No SQL, no joins.

### EC2

- Virtual servers. **This project creates zero EC2 instances.** Fargate runs on EC2 that AWS hides.
- The **EC2 console** also holds load balancers, target groups, security groups and Elastic IPs. That's why you go there.
- In CI/CD work EC2 shows up as build runners, older deploy targets, and those console sections.

### Finding resources in the console

- Set the region (top right) to **US West (Oregon) us-west-2**. The console defaults to N. Virginia and looks empty.
- Check that the account ID is `1941-6920-9897`.
- IAM and S3 are global. Everything else is per region.
- See everything at once: **Tag Editor**, region `us-west-2`, tag `Project = notes`. Every resource has it via `default_tags`.

### What costs money per hour

The **NAT gateway** and the **ALB** (~$0.13/hr combined), plus a little Fargate. The rest is free or pennies at this scale.

---

## 5. All 46 resources, by console location

| Console | Resources |
|---|---|
| **VPC** (15) | VPC, 4 subnets, internet gateway, NAT gateway + Elastic IP, 2 route tables, 4 route table associations |
| **EC2** (8) | ALB, listener, 2 listener rules, 2 target groups, 2 security groups |
| **ECS** (7) | Cluster, 3 services, 3 task definitions |
| **ECR** (6) | 3 repos + 3 lifecycle policies (keep the newest 5 images) |
| **IAM** (7) | Execution role + managed policy attachment, 3 task roles, 2 inline `dynamodb-notes` policies |
| **DynamoDB** (1) | `notes-dev-notes` |
| **CloudWatch** (3) | Log groups `/ecs/notes-dev/{web,api,worker}` |
| **S3** (3, from `bootstrap/`) | State bucket, versioning, public access block |

AWS also creates things Terraform doesn't track: running tasks, network interfaces, and the VPC's default route table, NACL and security group.

List them yourself: `terraform state list`

---

## 6. Terraform concepts

### The loop

**write → `plan` → `apply`.** You describe the end result, `plan` shows the difference, `apply` makes it. Always read the plan.

### State

- A record mapping your code (`aws_lb.this`) to the real thing in AWS.
- `terraform/dev` keeps it in S3, with `use_lockfile` so two runs can't write at once.
- **Drift** = someone changed AWS by hand, and state no longer matches reality.
- Never commit state. It can hold secrets.

### Anatomy of a project

A project is **a folder**. Terraform reads **every `.tf` file in it** (not subfolders) and combines them. File names are only convention.

```
folder/                     ← ROOT MODULE: where you run commands. Only it has state
├── versions.tf    terraform { required_version, required_providers, backend }
├── variables.tf   variable { }   → var.x
├── main.tf        locals { }, resource { }, data { }, module { }
├── outputs.tf     output { }
└── modules/x/                ← CHILD MODULE: a "function". variables = parameters,
                                 outputs = return values. Can't see the caller's locals
```

Generated files:

| File | From | Commit? |
|---|---|---|
| `.terraform/` | `init` (providers, modules) | No |
| `.terraform.lock.hcl` | `init` (exact provider versions) | **Yes** |
| `terraform.tfstate` | `apply` | **Never** |

### What makes a project valid

Minimum: one `.tf` file. In practice: `required_providers`, a `provider` block if it needs settings, and at least one `resource`.

`terraform validate` (offline) checks syntax, that references exist, that types match, that arguments exist for that resource type, required module inputs, `each.` only inside `for_each`, and no circular references.

It does **not** check variable values, credentials, or whether AWS accepts the values (e.g. a target group name over 32 characters fails only at `apply`).

```
init      → downloads providers, sets up the backend
validate  → checks code (offline)
plan      → compares code vs state vs real AWS (needs credentials)
apply     → makes changes, updates state
destroy   → deletes everything in state
```

### Block anatomy

```hcl
resource "aws_cloudwatch_log_group" "this" {
#  kind   ↑ resource type            ↑ your local name
  for_each          = var.services                        # meta-argument
  name              = "/ecs/${var.name_prefix}/${each.key}"  # interpolation
  retention_in_days = 3
}
# address: aws_cloudwatch_log_group.this["api"]
```

Nested blocks have no `=`: `health_check { ... }`, not `health_check = { ... }`.

### Where values come from

| Prefix | Meaning |
|---|---|
| `var.x` | Input passed in from outside (like a function argument) |
| `local.x` | Named value defined in this folder |
| `module.x.y` / `aws_x.name.attr` | Output of another module or resource |

`name_prefix` is `local.name_prefix` in `terraform/dev/main.tf`, then passed into the module, where it becomes `var.name_prefix`.

### Expressions (all in `modules/services/main.tf`)

| Syntax | Meaning | Example |
|---|---|---|
| `[for x in list : f(x)]` | Build a **list** | `[for n in names : upper(n)]` |
| `{for k, v in map : k => v.port}` | Build a **map** | `{api = 8080, web = 80, ...}` |
| `... if cond` | Filter | keep services with `port > 0` |
| `cond ? a : b` | Conditional | port mapping only if `port > 0` |
| `merge(a, b)` | Combine maps, `b` wins | default env vars + per-service overrides |
| `jsonencode(...)` | HCL → JSON string | `container_definitions` |
| `dynamic "blk" { for_each = cond ? [1] : [] }` | Include a nested block only sometimes | `load_balancer` only for web services |
| `depends_on = [...]` | Ordering Terraform can't infer | service waits for listener rule |
| `optional(number, 256)` | Default for a missing object field | `cpu` in `services.yaml` |
| `data "aws_iam_policy_document"` | Build IAM JSON, create nothing | task role policy |

**`for` builds a value. `for_each` builds resources:** one per key, with `each.key` (`"api"`) and `each.value` (its settings).

References create the build order: `aws_iam_role.task[each.key].id` = "the role with the same key as me", so roles are built before policies.

### Reading a plan

| Symbol | Meaning |
|---|---|
| `+` | Create |
| `~` | Update in place |
| `-/+` | Destroy then create (replace). Look for `# forces replacement` |
| `-` | Destroy |
| `<=` | Read (data source) |

Real plans we ran against the live stack:

| Change | Result | Why |
|---|---|---|
| `retention_in_days` 3 → 7 | `~` update in place | AWS allows editing it |
| Security group `name` changed | `-/+` replace | AWS can't rename a security group |
| `-var image_tag=v2` | Task definition `-/+`, service `~` | Task definitions can't be edited: new revision, then a rolling deploy |

Think-throughs:
- **Renaming a key** in `services.yaml` = destroy + create every resource for it (including the ECR repo). A `moved {}` block tells Terraform it's a rename instead.
- **`count` vs `for_each`:** `count` uses positions `[0] [1] [2]`, so removing one shifts the rest and causes unrelated changes. `for_each` uses keys and is stable. That's why the services module uses it.
- **`-target`** also pulls in whatever the target depends on. Use it as a workaround, not routinely.

### Adding a service (Exercise 2)

1. Copy `apps/web` → `apps/docs`, and change the Dockerfile destination to `.../html/docs/index.html`
2. Add `docs` to `services.yaml` (`path_patterns: ["/docs*"]`, `priority: 150`, `health_check_path: /docs/`)
3. Plan: **8 to add, 0 to change**. Existing services aren't touched
4. Priority 150 must come before `/*` at 200, or web catches everything

No Terraform code changes: this is what adding image #46 at work looks like.

---

## 7. Tools and tips

- **VS Code:** install the **HashiCorp Terraform** extension (`hashicorp.terraform`) for colors, hover docs, Cmd+click to definitions, autocomplete and format on save. Add **HashiCorp HCL** for Terragrunt `.hcl` files.
- **`terraform console`**: try expressions live against real config, creating nothing.
- **`learn/`**: 12 lessons (variables → lists → maps → `for` → `for_each` → modules) using the built-in `terraform_data`, with 5 exercises at the bottom of `main.tf`. Run `terraform apply` there. Free.
- **zsh gotcha:** `R="--region us-west-2"; aws ... $R` fails, because zsh doesn't split variables into words. Use `export AWS_REGION=us-west-2` instead.

---

## 8. Still to do

- [ ] Exercise 1: console tour (ECS tasks and logs, target group health, listener rules, DynamoDB items)
- [ ] Exercise 2: apply `docs` (`apply -target=module.ecr` → `push-images.sh v1` → `apply`), open `<app_url>/docs/`
- [ ] Exercise 3: deploy `v2` of web (`push-images.sh v2`, `apply -var image_tag=v2`)
- [ ] Exercise 4: drift (set api desired count to 2 in the console, then `plan`)
- [ ] Exercise 5: break IAM (`dynamodb_access: false` on api, find `AccessDenied` in logs)
- [ ] Exercise 6: `terraform state list` / `state show`, find the state file in S3
- [x] `terraform destroy` in `terraform/dev` before the break (repeat after each session; keep `bootstrap/`)
- [ ] Monday: Terragrunt (`live/dev/`)
- [x] Commit `learn/`, `apps/docs/`, `services.yaml`, this file
