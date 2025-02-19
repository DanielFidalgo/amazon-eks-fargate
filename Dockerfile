FROM amazonlinux:2018.03
LABEL maintainer="Michael Hausenblas, hausenbl@amazon.com"

# install eksctl, IAM authenticator, kubectl, and jq:
RUN yum -y install shadow-utils unzip git && \
    curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/aws-iam-authenticator && \
    chmod +x ./aws-iam-authenticator && \
    mv ./aws-iam-authenticator /usr/local/bin && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    curl --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp && \
    mv /tmp/eksctl /usr/local/bin && \
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin  && \
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh && \
    JQ=/usr/bin/jq && \
    curl https://stedolan.github.io/jq/download/linux64/jq > $JQ && chmod +x $JQ

# copy from repo into container image:
COPY entrypoint.sh /entrypoint.sh

# make default on start-up:
ENTRYPOINT ["/entrypoint.sh"]
