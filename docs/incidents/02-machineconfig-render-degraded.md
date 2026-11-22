
# Incident 2: Worker MachineConfigPool degraded by an invalid MachineConfig

| Field | Value |
| --- | --- |
| Date | 2026-11-22 |
| Environment | Lab: OpenShift 4.21.42 on Azure (eastasia), 3 control-plane + 2 worker nodes |
| Severity | Medium: no running workload was affected, but all further worker configuration changes were blocked |
| Duration | About 5 minutes from detection to recovery |
| Type | Deliberately introduced (break-fix exercise) |

## Summary
A MachineConfig named `99-worker-broken` was applied with an invalid Ignition version (`9.9.9`). The Machine Config Operator could not render a new configuration for the worker pool, and the pool went to `DEGRADED=True`. No node was drained or rebooted, because the operator stops before applying anything it cannot render. Deleting the bad MachineConfig restored the pool.

## Symptom
`oc get mcp worker` showed `DEGRADED True`, while the nodes themselves stayed `Ready`:
