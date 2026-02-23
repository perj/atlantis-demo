# plan-readonly-kubernetes-job

An Atlantis addon that runs `terraform plan` inside a dedicated Kubernetes Job pod, using a readonly service account. The read-write SA token is never present in the pod that executes plan — the Job is started with only the readonly SA, so provider and module code running during plan is structurally incapable of making write calls to the API.

This is a self-contained alternative to the [`plan-readonly-bwrap`](../plan-readonly-bwrap/) addon. Both achieve the same credential isolation goal; the approaches differ in where the plan runs:

| Approach | Where plan runs | Isolation mechanism |
|---|---|---|
| **`plan-readonly-kubernetes-job`** | Separate Kubernetes Job pod | Pod identity: the Job pod is started with the readonly SA |
| `plan-readonly-bwrap` | Inside the existing Atlantis pod | Mount namespace: bwrap bind-mounts the readonly token over the rw token |

## How it works

### Credential flow

Two Kubernetes service accounts are created:

- **Main SA** (`atlantis-<instance>`) — `edit` role on target namespaces. Used by Atlantis for `apply` and for all housekeeping outside the plan step.
- **Readonly SA** (`atlantis-<instance>-readonly`) — `view` role plus a supplemental role for RBAC reads (needed to refresh state for configurations that manage `roles`/`rolebindings`). The plan Job runs as this SA.

### The plan Job

`plan-in-job.sh` is the custom plan step. It:

1. Discovers the Atlantis image currently running so the Job uses the same terraform binary.
2. Submits a `batch/v1 Job` whose pod runs as the readonly SA, mounts the shared workspace PVC, and shadows `~/.kube/` with an empty `emptyDir` so the main pod's elevated kubeconfig is never accessible inside the Job.
3. The terraform container builds its own kubeconfig in `/tmp/.kube/` from its injected SA token (in-cluster credentials), sets `HOME=/tmp`, and runs `terraform init` + `terraform plan`.
4. Streams the Job pod logs back to Atlantis (and hence into the PR comment).
5. Checks Job completion status and exits non-zero on failure.
6. Cleans up the Job on exit (success or failure).

### IRSA / cloud credentials

This pattern maps cleanly to AWS IRSA. In a real setup:

- The readonly SA is annotated with `eks.amazonaws.com/role-arn: <readonly-role-arn>`.
- The main SA is annotated with `eks.amazonaws.com/role-arn: <readwrite-role-arn>`.
- The EKS OIDC webhook automatically injects the correct AWS credentials into each pod based on its SA annotation — no credential plumbing in the script is required at all.
- `terraform plan` runs with readonly IAM permissions; `terraform apply` runs with read-write IAM permissions.

### Server-side workflow enforcement

The Atlantis server configuration (`repos.yaml`, embedded in the deployment) defines the default workflow and sets `allow_custom_workflows: false`. Repositories cannot override the plan step or define their own workflows — they can only declare project directories and autoplan triggers. This prevents a repository from bypassing isolation by substituting its own plan command.

## Storage considerations

The workspace PVC uses `ReadWriteOnce` (RWO) access mode. RWO is a node-level restriction: only one node may mount the volume at a time. The Job spec includes a pod affinity rule that pins the plan Job to the same node as the Atlantis pod to ensure the volume can be mounted.

In a multi-node cluster, use `ReadWriteMany` storage (EFS on AWS, Azure Files, or an NFS-backed StorageClass) instead. That removes the scheduling constraint and also supports running Atlantis with multiple replicas. The relevant comment and the affinity block in `plan-in-job.sh` explain the trade-off.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Kubernetes resources: two SAs, RBAC, job-manager Role, webhook secret, ConfigMaps (repos.yaml + plan script), Deployment, Service, Ingress |
| `variables.tf` | Input variables |
| `outputs.tf` | Outputs: Atlantis URL, webhook URL, webhook secret, GitLab webhook setup command |
| `backend.tf` | S3 backend pointing at the local MinIO instance |
| `plan-in-job.sh` | Custom plan step: spawns the readonly Job pod, streams logs, checks outcome |
| `atlantis.yaml` | Example repo-level project definitions (for use in repositories managed by this instance) |
| `setup.sh` | End-to-end setup: runs `terraform apply`, creates the GitLab group/repo, pushes demo content, configures the webhook and approval rules |

## Prerequisites

The base demo environment (scripts 01–08) must be running before `setup.sh` is executed. `setup.sh` assumes:

- `kubectl` context `kind-atlantis-demo` is active.
- The GitLab root token secret exists in the `gitlab` namespace.
- The `atlantis-bot` GitLab user has been created (script 05).
- The `system-alpha` namespace exists (used as the target namespace).

## Setup

```bash
cd extras/plan-readonly-kubernetes-job
./setup.sh
```

When complete, the script prints the Atlantis URL and the GitLab repository URL.

## Trying it

1. Open a branch in the `readonly-job/readonly-job-infra` repository and make a change to any `.tf` file.
2. Open a merge request. Atlantis will comment with the plan output.
3. The plan log will show `==> Spawning isolated plan Job '...'` followed by terraform output streamed from the Job pod.
4. Approve the MR and comment `atlantis apply`. Apply runs in the main Atlantis pod using the main SA (full edit permissions).

To verify the credential isolation directly, temporarily remove the `view` RoleBinding for the readonly SA in the `system-alpha` namespace and confirm that `terraform plan` fails with a permission error — confirming that the main SA's credentials are not used as a fallback during plan.
