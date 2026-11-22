#!/bin/bash
# Re-applies Phase 2 and Phase 3 after a rebuild. Contains no secrets.
set -e
export KUBECONFIG=$HOME/clusters/azure-4.21/auth/kubeconfig
REPO=$HOME/openshift-azure-lab

echo "== Phase 2: identity"
oc create secret generic htpass-secret --from-file=htpasswd=$HOME/secrets/users.htpasswd -n openshift-config --dry-run=client -o yaml | oc apply -f -
oc apply -f $REPO/platform/identity/

echo "== etcd encryption"
oc patch apiserver cluster --type=merge -p '{"spec":{"encryption":{"type":"aesgcm"}}}'

echo "== Phase 3: tenants"
oc apply -f $REPO/platform/tenants/team-a-dev/

echo "== Waiting for the authentication operator to settle"
sleep 60
oc wait co/authentication --for=condition=Progressing=False --timeout=600s
oc get co authentication

echo "Done. Next: test alice, then delete kubeadmin."
echo "== Project template"
oc apply -f $HOME/openshift-azure-lab/platform/project-template/template.yaml
oc patch project.config.openshift.io/cluster --type=merge -p '{"spec":{"projectRequestTemplate":{"name":"project-request"}}}'
echo "== Ingress certificate (Let's Encrypt, from ~/secrets)"
CERTDIR=$HOME/secrets/letsencrypt/live/apps.ocp-lab.imranmallick.in
oc create secret tls letsencrypt-apps --cert=$CERTDIR/fullchain.pem --key=$CERTDIR/privkey.pem -n openshift-ingress --dry-run=client -o yaml | oc apply -f -
oc patch ingresscontroller.operator default -n openshift-ingress-operator --type=merge -p '{"spec":{"defaultCertificate":{"name":"letsencrypt-apps"}}}'
