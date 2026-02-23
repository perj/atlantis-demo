#!/bin/bash
# plan-in-job.sh
#
# Custom Atlantis plan step: runs terraform plan inside an isolated Kubernetes
# Job using the readonly service account. The Job pod literally cannot receive
# the read-write SA token, so any provider or module code that runs during
# plan cannot make write calls to the infrastructure API.
#
# In a real AWS/IRSA setup, swapping the SA is all that's needed — the EKS
# OIDC webhook injects the matching IAM role credentials automatically.
#
# Environment variables supplied by Atlantis:
#   DIR          - absolute path to the project directory
#   PLANFILE     - absolute path where the plan output must be written
#   PROJECT_NAME - used for Job naming
#   PULL_NUM     - used for Job naming
#   WORKSPACE    - terraform workspace
#
# Environment variables injected into the pod by main.tf:
#   ATLANTIS_INSTANCE - e.g. "system-alpha"
#   POD_NAMESPACE     - the pod's own namespace (via Downward API)

set -euo pipefail

: "${ATLANTIS_INSTANCE:?ATLANTIS_INSTANCE env var not set (should be injected by main.tf deployment)}"
: "${POD_NAMESPACE:?POD_NAMESPACE env var not set (should be injected by main.tf deployment)}"
: "${DIR:?}"
: "${PLANFILE:?}"
: "${PROJECT_NAME:?}"
: "${PULL_NUM:?}"
: "${WORKSPACE:?}"

READONLY_SA="atlantis-${ATLANTIS_INSTANCE}-readonly"
PVC_NAME="atlantis-${ATLANTIS_INSTANCE}-data"

# kubectl was installed to /home/atlantis/.bin/ by the install-kubectl init
# container defined in main.tf.
export PATH="/home/atlantis/.bin:${PATH}"

# Build a DNS-safe Job name: lowercase alphanumeric + hyphens, max 63 chars.
SAFE_ID=$(printf '%s-%s-%s' "$PROJECT_NAME" "$PULL_NUM" "$WORKSPACE" \
  | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-\+/-/g; s/^-//; s/-$//' \
  | cut -c1-42)
JOB_NAME="plan-${SAFE_ID}-$(tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c4 || printf '%04x' $$)"

cleanup() {
  kubectl delete job "$JOB_NAME" -n "$POD_NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Discover the image currently running in this Atlantis pod so the Job uses
# the same bundled terraform version.
ATLANTIS_IMAGE=$(kubectl get pods -n "$POD_NAMESPACE" \
  -l "instance=${ATLANTIS_INSTANCE}" \
  -o jsonpath='{.items[0].spec.containers[0].image}')

echo "==> Spawning isolated plan Job '${JOB_NAME}'"
echo "    Service account : ${READONLY_SA}"
echo "    Image           : ${ATLANTIS_IMAGE}"
echo "    Project dir     : ${DIR}"
echo "    Plan file       : ${PLANFILE}"
echo ""

# Note: PLANFILE and WORKSPACE are expanded here (outer shell), so the Job
# spec gets literal values rather than shell variable references.
kubectl create -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${POD_NAMESPACE}
  labels:
    app.kubernetes.io/name: atlantis
    app.kubernetes.io/instance: ${ATLANTIS_INSTANCE}
    app.kubernetes.io/component: plan-job
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 0
  template:
    spec:
      serviceAccountName: ${READONLY_SA}
      restartPolicy: Never

      # Pin the Job to the same node as the Atlantis pod.
      #
      # The workspace PVC uses ReadWriteOnce, which is a node-level restriction:
      # only one node can mount it at a time. Without this affinity, the Job
      # could be scheduled to a different node and fail to mount the volume on
      # cloud block storage (EBS, Azure Disk, etc.).
      #
      # Alternative for multi-node clusters: use ReadWriteMany storage (e.g.
      # EFS on AWS, Azure Files, or an NFS-backed StorageClass). That removes
      # the scheduling constraint entirely and is the better choice if Atlantis
      # itself ever needs HA (multiple replicas).
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                instance: ${ATLANTIS_INSTANCE}
            topologyKey: kubernetes.io/hostname

      containers:
      - name: terraform
        image: ${ATLANTIS_IMAGE}
        workingDir: ${DIR}
        command:
        - sh
        - -c
        - |
          set -e
          # Build a kubeconfig in /tmp using this pod's readonly SA token.
          # Writing to /tmp (not the shared PVC) avoids any race with the
          # main Atlantis pod's ~/.kube/config. HOME is also set to /tmp so
          # the terraform kubernetes provider resolves ~/.kube/config here.

          # Note: In a production setup a kubeconfig likely isn't needed, we
          # use it here to allow setting a specific context in the terraform
          # provider, which is a demo-specific requirement.

          export PATH="/home/atlantis/.bin:\${PATH}"
          mkdir -p /tmp/.kube
          kubectl config set-cluster in-cluster \
            --server=https://kubernetes.default.svc \
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
            --kubeconfig=/tmp/.kube/config
          kubectl config set-credentials readonly \
            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
            --kubeconfig=/tmp/.kube/config
          kubectl config set-context kind-atlantis-demo \
            --cluster=in-cluster --user=readonly \
            --kubeconfig=/tmp/.kube/config
          kubectl config use-context kind-atlantis-demo --kubeconfig=/tmp/.kube/config

          TF_BIN="/home/atlantis/.atlantis/bin/terraform\${TF_VERSION}"
          if [ ! -x "\$TF_BIN" ]; then
            echo "ERROR: terraform binary not found at \$TF_BIN"
            echo "Atlantis should have pre-downloaded it before running this step."
            exit 1
          fi
          echo "==> Using \$TF_BIN"

          echo "==> terraform init"
          "\$TF_BIN" init -input=false -no-color

          if [ "\$TF_WORKSPACE" != "default" ]; then
            echo "==> terraform workspace select \$TF_WORKSPACE"
            "\$TF_BIN" workspace select "\$TF_WORKSPACE" 2>/dev/null \
              || "\$TF_BIN" workspace new "\$TF_WORKSPACE"
          fi

          echo "==> terraform plan"
          "\$TF_BIN" plan -input=false -no-color -out="\$TF_PLAN_FILE"
        env:
        - name: TF_WORKSPACE
          value: "${WORKSPACE}"
        - name: TF_PLAN_FILE
          value: "${PLANFILE}"
        # Atlantis pre-downloads the project's terraform version to
        # ~/.atlantis/bin/terraform{version} before running any steps, and
        # exposes it as $ATLANTIS_TERRAFORM_VERSION. We pass it here so the
        # Job uses exactly the same binary rather than whatever is baked into
        # the Atlantis image.
        - name: TF_VERSION
          value: "${ATLANTIS_TERRAFORM_VERSION}"
        - name: TF_IN_AUTOMATION
          value: "true"
        - name: HOME
          value: /tmp
        - name: KUBECONFIG
          value: /tmp/.kube/config
        # MinIO/S3 credentials for the terraform state backend.
        # In a real IRSA setup these would also come from the IAM role.
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: AWS_ACCESS_KEY_ID
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: AWS_SECRET_ACCESS_KEY
        volumeMounts:
        - name: workspace
          mountPath: /home/atlantis
        # Shadows the PVC's .kube/ with an empty pod-local dir so the
        # elevated kubeconfig written by the main Atlantis pod is never
        # visible inside this container. The terraform provider and kubectl
        # commands use /tmp/.kube/config (HOME=/tmp) instead.
        - name: kube-config
          mountPath: /home/atlantis/.kube

      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: ${PVC_NAME}
      - name: kube-config
        emptyDir: {}
EOF

# ---- Wait for the Job pod to appear ----------------------------------------

echo "==> Waiting for Job pod..."
POD=""
for _ in $(seq 1 30); do
  POD=$(kubectl get pods -n "$POD_NAMESPACE" -l "job-name=${JOB_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$POD" ] && break
  sleep 2
done

if [ -z "$POD" ]; then
  echo "ERROR: Job pod did not appear within 60s"
  kubectl describe job "$JOB_NAME" -n "$POD_NAMESPACE" || true
  exit 1
fi

# ---- Stream logs ------------------------------------------------------------

echo "==> Streaming logs from pod '${POD}'..."
echo ""
kubectl wait pod "$POD" -n "$POD_NAMESPACE" --for=condition=Ready --timeout=120s >/dev/null
kubectl logs -n "$POD_NAMESPACE" -f "$POD" -c terraform 2>&1 || true

# ---- Check outcome ----------------------------------------------------------
# After kubectl logs -f returns (container exited), give the Job controller a
# moment to update its status, then check.

if ! kubectl wait job "$JOB_NAME" -n "$POD_NAMESPACE" \
    --for=condition=Complete --timeout=30s 2>/dev/null; then
  echo ""
  echo "ERROR: plan Job did not complete successfully"
  kubectl logs -n "$POD_NAMESPACE" "$POD" -c terraform --tail=30 2>/dev/null || true
  exit 1
fi

echo ""
echo "==> Isolated plan complete."
