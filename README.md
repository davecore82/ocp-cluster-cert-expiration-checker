# OpenShift Certificate Expiration Checker

A lightweight script to determine how long an OpenShift cluster can safely remain shut down without requiring manual CSR approval.

## Problem

When an OpenShift cluster is shut down for an extended period, kubelet certificates may expire. When the cluster restarts, these expired certificates require manual CSR (Certificate Signing Request) approval, which can be tedious for large clusters.

## Solution

This script checks kubelet certificate expiration dates across all nodes and calculates the safe shutdown window, avoiding the need to install heavy operators like cert-utils-operator.

## Prerequisites

- `oc` CLI tool installed
- Active login to an OpenShift cluster (`oc login`)
- Permissions to debug nodes

## Usage

```bash
./check-cluster-cert-expiry.sh
```

## What It Checks

The script examines:
- **Kubelet client certificates** (`/var/lib/kubelet/pki/kubelet-client-current.pem`)
- **Kubelet server certificates** (`/var/lib/kubelet/pki/kubelet-server-current.pem`)

These are the critical certificates that, if expired during shutdown, will require manual CSR approval on cluster restart.

## Output

The script provides:
1. Certificate expiration dates for each node
2. Days remaining until expiration
3. Color-coded warnings (red < 7 days, yellow < 30 days, green > 30 days)
4. **Safe shutdown period** - how long you can keep the cluster powered off

## Example Output

```
======================================================
OpenShift Cluster Certificate Expiration Checker
======================================================

Cluster: https://api.cluster.example.com:6443
User: admin

=== Checking Kubelet Certificates on All Nodes ===

Node: master-0
  Kubelet Client Cert: notAfter=May 29 12:34:56 2026 GMT
  Days remaining: 30
  Kubelet Server Cert: notAfter=May 29 12:34:56 2026 GMT
  Days remaining: 30

Node: worker-0
  Kubelet Client Cert: notAfter=May 28 10:15:22 2026 GMT
  Days remaining: 29
  Kubelet Server Cert: notAfter=May 28 10:15:22 2026 GMT
  Days remaining: 29

======================================================
=== Summary ===
======================================================

Minimum days until certificate expiration: 29 days

Safe shutdown period: Up to 27 days (with 2-day safety margin)

Recommendation: Keep shutdown period under 27 days to avoid CSR approval requirement.

NOTE: Kubelet certificates typically rotate every 30 days in OpenShift.
      If certs expire during shutdown, manual CSR approval will be required on restart.
======================================================
```

## Key Points

- **Kubelet certificates rotate every 30 days** by default in OpenShift
- The script includes a **2-day safety margin** in its recommendations
- If certificates expire during shutdown, you'll need to manually approve CSRs on restart
- **Safe practice**: Shut down for no more than 2-3 weeks if you want to avoid manual intervention

## Alternative to Operator

This script provides the same critical information as the cert-utils-operator but without:
- Installing a cluster-wide operator
- Additional resource consumption
- Operator lifecycle management

## Troubleshooting

**"Error: Not logged into an OpenShift cluster"**
- Run `oc login` first

**"Unable to retrieve certificate"**
- Ensure you have permissions to debug nodes
- Check if the certificate paths exist on your cluster version

**Date parsing errors on macOS**
- The script handles both GNU date (Linux) and BSD date (macOS) automatically

## Related Documentation

- [Graceful Cluster Shutdown](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/backup_and_restore/graceful-shutdown-cluster)
- [Hibernating a Cluster](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html-single/backup_and_restore/index#hibernating-cluster)
- [Approving CSRs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/nodes/working-with-nodes#nodes-nodes-working-about_nodes-nodes-working)
