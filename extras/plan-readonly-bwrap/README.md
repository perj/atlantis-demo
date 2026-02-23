# plan-readonly-bwrap

An Atlantis addon that runs `terraform plan` inside a [bubblewrap](https://github.com/containers/bubblewrap) (bwrap) sandbox, replacing the read-write Kubernetes service account token with a short-lived readonly token for the duration of the plan. The read-write token is  inaccessible to any provider or module code running during plan.

This is a self-contained alternative to the [`plan-readonly-kubernetes-job`](../plan-readonly-kubernetes-job/) addon. Both achieve the same credential isolation goal; the approaches differ in where the plan runs:

| Approach | Where plan runs | Isolation mechanism |
|---|---|---|
| `plan-readonly-kubernetes-job` | Separate Kubernetes Job pod | Pod identity: the Job pod is started with the readonly SA |
| **`plan-readonly-bwrap`** | Inside the existing Atlantis pod | Mount namespace: bwrap bind-mounts the readonly token over the rw token |

## How it works

### Credential flow

Two Kubernetes service accounts are created:

- **Main SA** (`atlantis-<instance>`) — `edit` role on target namespaces. Used by Atlantis for `apply` and for all housekeeping outside the plan step.
- **Readonly SA** (`atlantis-<instance>-readonly`) — `view` role plus a custom role for RBAC and secret reads (needed to refresh state for configurations that manage those resources). Used only inside the bwrap sandbox during plan.

The main SA also holds a narrowly-scoped Role that allows it to call the Kubernetes TokenRequest API for the readonly SA only. The plan script uses this to mint a short-lived token (15-minute expiry) at the start of each plan.

### The bwrap sandbox

`plan-bwrap.sh` is the custom plan step. It:

1. Mints a short-lived readonly token via `curl` to the in-cluster TokenRequest API.
2. Writes the token and a matching kubeconfig to a host-side temp directory.
3. Invokes `bwrap`.
4. Runs `terraform plan` inside the sandbox.

Because the rw token path is shadowed by a bind mount, provider code running inside bwrap has no path to read it.

### Why the kubeconfig is replaced

The `kubernetes` Terraform provider reads its credentials from either the SA token path _or_ a kubeconfig file. Replacing only the SA token is not enough if the provider is configured to use a kubeconfig context. This addon replaces both.

In a production AWS/IRSA setup, `AWS_WEB_IDENTITY_TOKEN_FILE` (the projected token the AWS SDK uses for `sts:AssumeRoleWithWebIdentity`) would also need to be bind-mounted away, and `AWS_ROLE_ARN` overridden via `--setenv`. The comments in `plan-bwrap.sh` show how.

### Server-side workflow enforcement

The Atlantis server configuration (`repos.yaml`, embedded in the deployment) defines the default workflow and sets `allow_custom_workflows: false`. Repositories cannot override the plan step or define their own workflows — they can only declare project directories and autoplan triggers. This prevents a repository from bypassing the sandbox by substituting its own plan command.

## Why the container runs as root

bwrap uses `clone(CLONE_NEWNS)` and `mount()` to create the credential sandbox. Both require `CAP_SYS_ADMIN` in the process's _effective_ capability set.

Kubernetes `capabilities.add` places a capability in the container's _permitted_ set and the _bounding_ set. For a non-root process, permitted capabilities are not automatically promoted to the effective set — the process must raise them itself or use a setuid binary. In practice, non-root processes start with an empty effective set and have no mechanism to raise arbitrary capabilities from permitted.

Running as root (`run_as_user: 0`) means permitted capabilities are immediately in the effective set, so bwrap can call `clone(CLONE_NEWNS)` and `mount()` without any additional privilege setup.

**Why not setuid bwrap?** The conventional workaround for non-root bwrap usage is to install the binary setuid root. This does not work reliably in containers: when a setuid binary executes, the kernel grants it the permitted capabilities up to the _bounding_ set. bwrap's setuid startup path calls `capset()` to configure its capability set, and this fails if the bounding set is missing capabilities bwrap expects to have. Container runtimes apply a restricted bounding set by default, making setuid bwrap fragile.

**Security implications.** Running as root means provider code executing inside the bwrap sandbox also runs as root (UID 0). The sandbox still enforces credential isolation — the rw SA token is bind-mounted away and is not readable regardless of UID. What root _can_ do is write to writable paths inside the sandbox (`$DIR`, `/tmp`) and potentially exploit a kernel vulnerability to escape the namespace. For a demo environment this is an acceptable trade-off; the key property being demonstrated is credential isolation, not UID isolation. In a hardened production setup you would want to combine the bwrap mount namespace with a user namespace that maps the child process to a non-root UID — but doing this correctly when the caller is already root requires explicit `uid_map`/`gid_map` configuration that bwrap does not expose directly via CLI flags.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Extends the Atlantis image with `bubblewrap` and `jq` (used to parse the TokenRequest response) |
| `main.tf` | Kubernetes resources: two SAs, RBAC, token-mint permission, webhook secret, ConfigMaps, Deployment, Service, Ingress |
| `variables.tf` | Input variables |
| `outputs.tf` | Outputs: Atlantis URL, webhook URL, webhook secret, GitLab webhook setup command |
| `backend.tf` | S3 backend pointing at the local MinIO instance |
| `plan-bwrap.sh` | Custom plan step: mints readonly token, builds kubeconfig, runs bwrap sandbox |
| `atlantis.yaml` | Example repo-level project definitions (for use in repositories managed by this instance) |
| `setup.sh` | End-to-end setup: builds and loads the Docker image, runs `terraform apply`, creates the GitLab group/repo, pushes demo content, configures the webhook and approval rules |

## Prerequisites

The base demo environment (scripts 01–08) must be running before `setup.sh` is executed. `setup.sh` assumes:

- `kubectl` context `kind-atlantis-demo` is active.
- The GitLab root token secret exists in the `gitlab` namespace.
- The `atlantis-bot` GitLab user has been created (script 05).
- The `system-alpha` namespace exists (used as the target namespace).

## Setup

```bash
cd extras/plan-readonly-bwrap
./setup.sh
```

When complete, the script prints the Atlantis URL and the GitLab repository URL.

## Trying it

1. Open a branch in the `readonly-bwrap/readonly-bwrap-infra` repository and make a change to any `.tf` file.
2. Open a merge request. Atlantis will comment with the plan output.
3. The plan log will show `==> Minting readonly token for SA 'atlantis-readonly-bwrap-readonly'` followed by `==> terraform plan (bwrap sandbox, ...)`.
4. Approve the MR and comment `atlantis apply`. Apply runs outside the sandbox using the main SA (full edit permissions).

To verify the credential isolation directly, you can inspect which SA performed the plan by checking recent Kubernetes API audit logs, or by temporarily removing the `view` RoleBinding for the readonly SA and confirming that `terraform plan` fails with a permission error rather than using the rw SA as a fallback.
