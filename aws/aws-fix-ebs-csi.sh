#!/bin/bash

export AWS_REGION="eu-west-1"
export CLUSTER_NAME="aichemy-test-cluster"
export AWS_ACCOUNT_ID="719768632770"

# Get OIDC ID
OIDC_ID=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d '/' -f 5)

echo "OIDC ID: ${OIDC_ID}"

# Create trust policy
cat > /tmp/ebs-csi-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
          "oidc.eks.${AWS_REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --assume-role-policy-document file:///tmp/ebs-csi-trust-policy.json \
  --region ${AWS_REGION}

# Attach policy
aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --region ${AWS_REGION}

# Get role ARN
ROLE_ARN=$(aws iam get-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --query 'Role.Arn' \
  --output text)

echo "Role ARN: ${ROLE_ARN}"

# Annotate service account
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=${ROLE_ARN} \
  --overwrite

# Restart CSI driver pods
kubectl rollout restart deployment ebs-csi-controller -n kube-system
kubectl rollout restart daemonset ebs-csi-node -n kube-system

echo "Attendere ~30 secondi, poi verificare:"
echo "kubectl get pods -n kube-system | grep ebs-csi"
echo "kubectl delete pvc -n minio --all"
echo "kubectl delete pod -n minio --all"
