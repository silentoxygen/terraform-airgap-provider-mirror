FROM nginx:alpine

RUN apk add --no-cache openssl
RUN mkdir -p /etc/nginx/certs

RUN cat > /tmp/openssl.cnf <<EOF
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = tf-mirror

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = tf-mirror
EOF

RUN openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/nginx/certs/mirror.key \
  -out /etc/nginx/certs/mirror.crt \
  -config /tmp/openssl.cnf \
  -extensions v3_req

# nginx https config
COPY /tf-mirror-server/nginx-mirror.conf /etc/nginx/conf.d/default.conf

# mirror content goes here
COPY terraform-providers/ /usr/share/nginx/html/

EXPOSE 443
