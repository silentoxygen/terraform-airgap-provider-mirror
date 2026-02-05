FROM hashicorp/terraform:1.5

USER root

RUN apk add --no-cache ca-certificates

COPY mirror.crt /usr/local/share/ca-certificates/tf-mirror.crt
RUN update-ca-certificates

WORKDIR /work
ENV TF_CLI_CONFIG_FILE=/work/terraform.rc

CMD ["init"]
