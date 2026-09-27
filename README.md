# terra-practice

A small "notes" app on AWS, built to practice Terraform and Terragrunt before a real deployment.

- **3 container images** (`web`, `api`, `worker`) stand in for the 45 at work
- **ECS Fargate** runs the containers, an **ALB** routes traffic, and **DynamoDB** stores notes
- **Sunday:** deploy it with plain Terraform (`terraform/dev/`)
- **Monday:** deploy the same thing with Terragrunt (`live/dev/`)

```
Internet → ALB ─┬─ /api/*  → api    ─┐
                └─ /*      → web     ├─→ DynamoDB
                             worker ─┘   (heartbeat every 60s)
```

## Layout

| Path | What it is |
|---|---|
| `services.yaml` | **The inventory.** One entry per image. At work, this is where the 45 go. |
| `apps/` | Source code and a Dockerfile for each image |
| `scripts/push-images.sh` | Builds every app and pushes it to ECR |
| `bootstrap/` | Creates the S3 bucket that holds Terraform state (run once) |
| `modules/` | Reusable Terraform: `network`, `ecr`, `dynamodb`, `cluster`, `services` |
| `terraform/dev/` | Sunday: one plain Terraform root that wires the modules together |
| `live/` | Monday: the same deployment as Terragrunt units |

**Cost:** about $0.13/hour while running (mostly the NAT gateway and ALB). **Destroy at the end of every session.**

---

## Sunday: plain Terraform

### 1. Read before running (30 min)

Read in this order, and make sure you can say what each file does:

1. `services.yaml`
2. `modules/network/main.tf`: VPC, subnets, NAT, route tables
3. `modules/cluster/main.tf`: ECS cluster, ALB, execution role
4. `modules/services/main.tf`: **the most important file.** See how `for_each` turns the inventory into resources.
5. `terraform/dev/main.tf`: how modules pass outputs to each other

### 2. Create the state bucket

```bash
cd bootstrap
terraform init
terraform apply        # type "yes"
cd ..
```

This folder uses *local* state because the bucket can't store its own state before it exists.

### 3. Deploy

Docker Desktop must be running.

```bash
cd terraform/dev
terraform init -backend-config=backend.hcl
terraform validate
terraform plan                            # read it! ~46 resources

# ECR first, because images must exist before services can start
terraform apply -target=module.ecr
../../scripts/push-images.sh v1

terraform apply                           # everything else, ~5 min
terraform output app_url                  # open in a browser (give it 1–2 min)
```

Add a note. The "worker heartbeat" should show a time within a minute.

### 4. Exercises (this is where the learning happens)

1. **Look around the console:** ECS → cluster → services → tasks → logs. Then check EC2 → Load Balancers → target groups (are the targets healthy?).
2. **Add a 4th service.** This is exactly what adding image #46 at work looks like.
   - Copy `apps/web` to `apps/docs`, and in `apps/docs/Dockerfile` change the destination to `/usr/share/nginx/html/docs/index.html`.
   - Add a `docs` entry to `services.yaml`: copy `web`, then set `path_patterns: ["/docs*"]`, `priority: 150`, and `health_check_path: /docs/`.
   - Run `terraform plan` and read what it wants to create.
   - Run `terraform apply -target=module.ecr`, then `../../scripts/push-images.sh v1`, then `terraform apply`.
   - Open `<app_url>/docs/`.
3. **Deploy a new version.** Edit `apps/web/index.html`, run `../../scripts/push-images.sh v2`, then `terraform apply -var image_tag=v2`. Watch the rolling deploy in the ECS console.
4. **Drift.** In the console, change the `api` service's desired count to 2. Run `terraform plan`. What does it want to do?
5. **Break IAM.** Set `dynamodb_access: false` on `api`, apply, and try adding a note. Find the `AccessDenied` error in CloudWatch Logs (`/ecs/notes-dev/api`). Then put it back.
6. **State.** Run `terraform state list`, then `terraform state show module.cluster.aws_lb.this`. Find the state file in the S3 bucket.

### 5. Destroy (don't skip)

```bash
terraform destroy
```

Keep the `bootstrap/` bucket. Monday needs it, and it costs pennies.

---

## Monday: Terragrunt

Sunday's stack must be destroyed first, because both use the same resource names.

### 1. Read before running (30 min)

1. `live/root.hcl`: remote state and provider, defined once for every unit
2. `live/dev/env.hcl`: the only file that changes between environments
3. `live/dev/cluster/terragrunt.hcl`: `include`, `terraform.source`, and a `dependency` with `mock_outputs`
4. `live/dev/services/terragrunt.hcl`: four dependencies feeding one module

Compare against `terraform/dev/main.tf`. It's the same wiring, but each piece now has **its own state file**, so a mistake in `services` can't touch `network`.

### 2. Deploy

```bash
cd live/dev

terragrunt run --all plan          # mock_outputs let this work before anything exists

cd ecr && terragrunt apply && cd ..
../../scripts/push-images.sh v1

terragrunt run --all apply         # Terragrunt works out the order: network → cluster → services
cd cluster && terragrunt output alb_dns_name
```

On an older Terragrunt, use `run-all plan` / `run-all apply` instead of `run --all`.

### 3. Exercises

1. **Dependency graph:** run `terragrunt dag graph` in `live/dev` (or `graph-dependencies` on older versions).
2. **Change one unit only:** edit a service's `desired_count`, then `cd services && terragrunt apply`. Notice that nothing else is planned.
3. **Make prod (plan only):** `cp -r dev prod`, set `env = "prod"` in `prod/env.hcl`, then run `cd prod && terragrunt run --all plan`. Everything gets a `notes-prod-` name and its own state files. That's the whole point of Terragrunt. **Don't apply it.** Delete `prod/` afterwards.
4. **Look at the generated files:** in `.terragrunt-cache/`, find the `backend.tf` and `provider.tf` that `root.hcl` generated.

### 4. Destroy

```bash
cd live/dev
terragrunt run --all destroy
```

---

## Cleanup when you're completely done

```bash
cd bootstrap && terraform destroy
```

Then check **Billing → Bills** a day later to confirm nothing is still charging.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Tasks keep stopping, "CannotPullContainerError" | Images weren't pushed yet, or the tag doesn't match `image_tag` |
| Target group shows unhealthy | Wrong `health_check_path` or port; check the service's logs |
| `exec format error` in logs | Image architecture ≠ `cpu_architecture` (ARM64). Build with `--platform linux/arm64` |
| Terragrunt complains about `use_lockfile` | Update Terragrunt (`brew upgrade terragrunt`) |
| `Error acquiring the state lock` | A previous run crashed. Use `terraform force-unlock <ID>` (only if nothing else is running) |
| 503 from the ALB | No healthy targets yet; wait 1–2 minutes after apply |

## How this maps to the real project

| Here | At work |
|---|---|
| `services.yaml` with 3 entries | An inventory of 45+ images, each with ports, CPU/memory, secrets, and dependencies |
| One `services` module with `for_each` | Same pattern. Don't write 45 modules. |
| `live/dev/<unit>` | `live/<account>/<region>/<env>/<unit>` |
| `push-images.sh` | A CI pipeline that builds and pushes on merge |
| `environment` in `services.yaml` | Plus `secrets` from Secrets Manager / Parameter Store |
