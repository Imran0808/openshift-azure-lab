#!/bin/bash
# Rebuild bootstrap: secrets (never in Git), a few cluster settings, then Argo CD takes over from Git.
set -e
export KUBECONFIG=$HOME/clusters/azure-4.21/auth/kubeconfig
REPO=$HOME/openshift-azure-lab
CERTDIR=$HOME/secrets/letsencrypt/live/apps.ocp-lab.imranmallick.in

echo "== Secrets from ~/secrets"
oc create secret generic htpass-secret --from-file=htpasswd=$HOME/secrets/users.htpasswd -n openshift-config --dry-run=client -o yaml | oc apply -f -
oc create secret tls letsencrypt-apps --cert=$CERTDIR/fullchain.pem --key=$CERTDIR/privkey.pem -n openshift-ingress --dry-run=client -o yaml | oc apply -f -

echo "== Cluster settings (patches)"
oc patch apiserver cluster --type=merge -p '{"spec":{"encryption":{"type":"aesgcm"}}}'
oc patch ingresscontroller.operator default -n openshift-ingress-operator --type=merge -p '{"spec":{"defaultCertificate":{"name":"letsencrypt-apps"}}}'
oc patch project.config.openshift.io/cluster --type=merge -p '{"spec":{"projectRequestTemplate":{"name":"project-request"}}}'

echo "== OpenShift GitOps operator"
oc apply -f $REPO/bootstrap/01-gitops-operator.yaml
until oc get crd applications.argoproj.io >/dev/null 2>&1; do echo "waiting for Argo CD CRDs..."; sleep 15; done
until oc get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; do echo "waiting for Argo CD instance..."; sleep 15; done
oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '{"spec":{"rbac":{"policy":"g, system:cluster-admins, role:admin\ng, platform-admins, role:admin\n","scopes":"[groups]"}}}'
oc apply -f $REPO/bootstrap/02-argocd-cluster-admin.yaml

echo "== Hand the repo to Argo CD"
oc apply -f $REPO/gitops/apps/
sleep 120
oc get applications -n openshift-gitops

echo "== Waiting for authentication to settle"
oc wait co/authentication --for=condition=Progressing=False --timeout=600s
echo "Done. Next: test alice, then delete kubeadmin."
