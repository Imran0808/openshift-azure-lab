# Incident 1: nginx pod crashing under restricted-v2 SCC

## Symptom

Error or CrashLoopBackOff, with the restart count climbing. also see a PodSecurity warning.


## Diagnosis (commands and what each showed)
oc logs deployment/web -n team-a-dev
--> oc logs shows the app’s own error "/var/cache/nginx/client_temp" failed (13: Permission denied).

oc get pod -l app=web -n team-a-dev -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
--> restricted-v2. The \. escapes the dots inside the annotation name.

oc get pod -l app=web -n team-a-dev -o jsonpath='{.items[0].spec.containers[0].securityContext}{"\n"}'
--> runAsNonRoot, allowPrivilegeEscalation: false and dropped capabilities.

oc get namespace team-a-dev -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
--> prints the project’s user ID range, for example 1000700000/10000. OpenShift runs the pod as a random user ID from that range, never as root.

oc get events -n team-a-dev --sort-by=.lastTimestamp | tail -10
-->  oc get events ... | tail -10 lists the latest cluster events for the project, such as BackOff and container restarts.


## Root cause

the nginx image writes to folders owned by root and expects to run as root. Under restricted-v2, OpenShift runs it as a random non-root user, so the writes fail with Permission denied and the container crashes

## Fix
oc set image deployment/web nginx=docker.io/nginxinc/nginx-unprivileged:latest -n team-a-dev --kubeconfig=/tmp/bob.kubeconfig
--> triggers a new rollout. oc create deployment named the container after the image.

oc get pods -n team-a-dev -l app=web
--> nginx-unprivileged is nginx rebuilt to run without root. It listens on port 8080 instead of 80 and writes only to folders any user may write to. I haven’t tested it on your cluster, so if it also crashes, send me oc logs.

oc get pod -l app=web -n team-a-dev -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
--> Running, still under restricted-v2. The pod runs without weakening security. That’s the point of this fix.

## Why not anyuid
oc adm policy add-scc-to-user anyuid -z default -n team-a-dev

It lets every pod using the default service account in that project run as any user, including root. If an attacker breaks into one of those containers, root makes escaping to the node much easier. If a vendor’s app truly needs root, the safer pattern is a dedicated service account just for that app, with anyuid granted only to it, documented and reviewed. In an interview, explaining this difference is worth more than the fix itself.
## Prevention

