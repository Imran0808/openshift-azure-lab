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

~~~
<PASTE the oc get mcp worker output here>
~~~

## Diagnosis
1. Checked the pool status and its conditions:

~~~bash
oc get mcp worker
oc describe mcp worker | grep -i -B2 -A4 degraded
~~~

The condition showed a render failure:

~~~
<PASTE the RenderDegraded message here>
~~~

2. Listed MachineConfigs by creation time to find the most recent change:

~~~bash
oc get mc --sort-by=.metadata.creationTimestamp | tail -3
~~~

The newest object was `99-worker-broken`, which matched the time the pool degraded.

3. Confirmed in the controller logs:

~~~bash
oc logs -n openshift-machine-config-operator deployment/machine-config-controller -c machine-config-controller | grep -i broken | tail -5
~~~

~~~
<PASTE one relevant log line here>
~~~

## Root cause
The MachineConfig declared `spec.config.ignition.version: 9.9.9`, which is not a valid Ignition specification version. The Machine Config Operator merges every MachineConfig for a pool into one rendered config. The invalid version made the merge fail, so the operator marked the pool `RenderDegraded` and refused to roll out any new configuration to the workers.

## Impact
- Running pods and nodes were not affected. No drain, reboot or file change happened.
- Any further MachineConfig change for the worker pool would have been blocked until the bad object was removed.
- On a real cluster, a degraded pool also blocks cluster upgrades for that pool.

## Fix
Deleted the invalid MachineConfig and confirmed recovery:

~~~bash
oc delete mc 99-worker-broken
oc get mcp worker
~~~

The pool returned to `UPDATED=True`, `DEGRADED=False` without any reboot, because nothing had been applied.

## Why the cluster stayed safe
The Machine Config Operator validates and renders the merged config before touching any node. A config it cannot render never reaches a node. This is why changes to RHCOS nodes go through MachineConfigs instead of manual SSH edits.

## Prevention
- Generate MachineConfigs from Butane files (`butane` tool), which validates the format and fills in the correct Ignition version.
- Keep MachineConfigs in Git and review them in a pull request before applying.
- Test node changes on a small custom MachineConfigPool (one node) before the full worker pool.
- Watch `oc get mcp` after every MachineConfig change, and alert on `DEGRADED=True`.

## Commands used
| Command | Purpose |
| --- | --- |
| `oc get mcp` | Pool status: updated, updating, degraded, machine counts |
| `oc describe mcp worker` | Conditions with the exact error message |
| `oc get mc --sort-by=.metadata.creationTimestamp` | Find the most recent MachineConfig change |
| `oc logs ... machine-config-controller` | Controller-side detail of the render failure |
| `oc delete mc <name>` | Remove the bad config so the pool can render again |
