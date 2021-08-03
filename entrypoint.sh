#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o pipefail

if [ -n "${REGION}" ]; then
  TARGET_REGION=${REGION}
else
  TARGET_REGION=eu-west-1
fi

if [ -n "${CLUSTER}" ]; then
  CLUSTER_NAME=${CLUSTER}
else
  NOW=$(date '+%s')
  CLUSTER_NAME=$GITHUB_ACTOR-$NOW
fi

if [ -n "${VERSION}" ]; then
  CLUSTER_VERSION=${VERSION}
else
  CLUSTER_VERSION='1.21'
fi

echo "Provisioning EKS on Fargate cluster $CLUSTER_NAME in $TARGET_REGION"

# create EKS on Fargate cluster:
tmpdir=$(mktemp -d)
cat <<EOF >> ${tmpdir}/fg-cluster-spec.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $TARGET_REGION
  version: '$CLUSTER_VERSION'
iam:
  withOIDC: true
fargateProfiles:
  - name: defaultfp
    selectors:
      - namespace: serverless
      - namespace: kube-system
      - namespace: default
cloudWatch:
  clusterLogging:
    enableTypes: ["*"]
EOF
eksctl create cluster -f ${tmpdir}/fg-cluster-spec.yaml

# check if cluster if available
echo "Waiting for cluster $CLUSTER_NAME in $TARGET_REGION to become available"
sleep 10
cluster_status="UNKNOWN"
until [ "$cluster_status" == "ACTIVE" ]
do 
    cluster_status=$(eksctl get cluster $CLUSTER_NAME --region $TARGET_REGION -o json | jq -r '.[0].Status')
    sleep 3
done

# create serverless namespace for Fargate pods, make it the active namespace:
echo "EKS on Fargate cluster $CLUSTER_NAME is ready, configuring it:"
kubectl create namespace serverless
kubectl config set-context $(kubectl config current-context) --namespace=serverless

# patch kube-system namespace to run also on Fargate:
kubectl --namespace kube-system patch deployment coredns \
        --type json -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'

# allow the cluster to use AWS Identity and Access Management (IAM) for service accounts
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

# download an IAM policy that allows the AWS Load Balancer Controller to make calls to AWS APIs
curl -o ${tmpdir}/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json

# create an IAM policy using the policy
aws iam create-policy --policy-name AlbControllerIAMPolicy --policy-document file://${tmpdir}/iam_policy.json

# retrieve identity
Account=$(aws sts get-caller-identity | jq -r '.Account')

# create Service Account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=alb-controller \
  --attach-policy-arn=arn:aws:iam::${Account}:policy/AlbControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# adding eks charts
helm repo add eks https://aws.github.io/eks-charts

# adding eks charts
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r '.cluster.resourcesVpcConfig.vpcId')

# Install load balancer
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=alb-controller \
  --set region=$TARGET_REGION \
  --set vpcId=$VPC_ID \
  -n kube-system
  
# Generate .kube/config
aws eks --region $TARGET_REGION update-kubeconfig --name $CLUSTER_NAME