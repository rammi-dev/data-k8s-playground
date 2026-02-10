#
# Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
#

#/bin/bash
set -e

# Root certificate expires in 10y.
CA_EXPIRATION_DAYS=3650
# Certificates expire in a year.
EXPIRATION_DAYS=365

SECRET_NAME=$1
DOMAIN_NAMES=$2
ROOT_CA_FILE_NAME="ca"
CERT_FILE_NAME="tls"

# Admin certificate is stored in a separate secret allowing for separate
# access control.
ADMIN_CERT_FILE_NAME=${CERT_FILE_NAME}-admin
ADMIN_CN=admin
ADMIN_SECRET_NAME=${SECRET_NAME}-admin

# Set variables for certificate details
COMPANY="Dremio"
ORG="Engineering"

# Generate a private key for the root CA.
openssl genpkey -algorithm RSA -out ${ROOT_CA_FILE_NAME}.key -pkeyopt rsa_keygen_bits:2048

# Generate a self-signed root CA certificate.
openssl req -x509 \
    -new \
    -nodes \
    -key ${ROOT_CA_FILE_NAME}.key \
    -sha256 \
    -days $CA_EXPIRATION_DAYS \
    -out ${ROOT_CA_FILE_NAME}.crt \
    -subj "/C=US/ST=CA/L=San Francisco/O=$COMPANY/OU=$ORG/CN=root-ca"

# Generate private keys.
openssl genpkey -algorithm RSA -out ${CERT_FILE_NAME}.key -pkeyopt rsa_keygen_bits:2048
openssl genpkey -algorithm RSA -out ${ADMIN_CERT_FILE_NAME}.key -pkeyopt rsa_keygen_bits:2048

# Split DOMAIN_NAMES by comma and assign to an array.
IFS=',' read -ra DOMAINS <<< "$DOMAIN_NAMES"

# Get the first domain for the commonName_default.
FIRST_DOMAIN="${DOMAINS[0]}"

# Generate alt_names section dynamically.
ALT_NAMES=""
for i in "${!DOMAINS[@]}"; do
ALT_NAMES+="DNS.$((i+1)) = ${DOMAINS[i]}"$'\n'
done

# Create CSRs for the certificates with the DNS and admin names.
openssl req -new -key ${CERT_FILE_NAME}.key -out ${CERT_FILE_NAME}.csr -subj "/C=US/ST=CA/L=San Francisco/O=$COMPANY/OU=$ORG/CN=${FIRST_DOMAIN}"
openssl req -new -key ${ADMIN_CERT_FILE_NAME}.key -out ${ADMIN_CERT_FILE_NAME}.csr -subj "/C=US/ST=CA/L=San Francisco/O=$COMPANY/OU=$ORG/CN=$ADMIN_CN"

# Create a config file for SANs.
CSR_CONFIG_TEMPLATE="
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca # The extensions to add to the self-signed cert

[ req_distinguished_name ]
countryName                 = Country Name (2 letter code)
countryName_default         = US
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = CA
localityName                = Locality Name (eg, city)
localityName_default        = San Francisco
organizationName            = Organization Name (eg, company)
organizationName_default    = $COMPANY
organizationalUnitName      = Organizational Unit Name (eg, section)
organizationalUnitName_default = $ORG
commonName                  = Common Name (e.g. server FQDN or YOUR name)
commonName_default          = <COMMON_NAME>
commonName_max              = 64

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
<ALT_NAMES>
"

# Sign the the CSR with the root CA
CSR_CONFIG="${CSR_CONFIG_TEMPLATE//<COMMON_NAME>/$FIRST_DOMAIN}"
CSR_CONFIG="${CSR_CONFIG//<ALT_NAMES>/$ALT_NAMES}"
echo "$CSR_CONFIG" | cat > ${CERT_FILE_NAME}-ext.cnf
cat ${CERT_FILE_NAME}-ext.cnf
openssl x509 -req \
    -in ${CERT_FILE_NAME}.csr \
    -CA ${ROOT_CA_FILE_NAME}.crt \
    -CAkey ${ROOT_CA_FILE_NAME}.key \
    -CAcreateserial \
    -out ${CERT_FILE_NAME}.crt \
    -days $EXPIRATION_DAYS \
    -sha256 \
    -extfile ${CERT_FILE_NAME}-ext.cnf \
    -extensions req_ext

# Sign the admin CSR with the root CA
CSR_CONFIG="${CSR_CONFIG_TEMPLATE//<COMMON_NAME>/$AMIN_CN}"
CSR_CONFIG="${CSR_CONFIG//<ALT_NAMES>/DNS.1=admin$'\n'}"
echo "$CSR_CONFIG" | cat > ${ADMIN_CERT_FILE_NAME}-ext.cnf
cat ${ADMIN_CERT_FILE_NAME}-ext.cnf
openssl x509 -req \
    -in ${ADMIN_CERT_FILE_NAME}.csr \
    -CA ${ROOT_CA_FILE_NAME}.crt \
    -CAkey ${ROOT_CA_FILE_NAME}.key \
    -CAcreateserial \
    -out ${ADMIN_CERT_FILE_NAME}.crt \
    -days $EXPIRATION_DAYS \
    -sha256 \
    -extfile ${ADMIN_CERT_FILE_NAME}-ext.cnf \
    -extensions req_ext

# Create the Kubernetes secret, make sure it does not exist before creating it.
kubectl delete secret $SECRET_NAME --ignore-not-found
kubectl create secret generic $SECRET_NAME \
--from-file=${CERT_FILE_NAME}.crt \
--from-file=${CERT_FILE_NAME}.key \
--from-file=${ROOT_CA_FILE_NAME}.crt \
--dry-run=client -o yaml | kubectl apply -f -

# Rename admin files as they are required to use the same names.
rm ${CERT_FILE_NAME}.crt ${CERT_FILE_NAME}.key
mv ${ADMIN_CERT_FILE_NAME}.crt ${CERT_FILE_NAME}.crt
mv ${ADMIN_CERT_FILE_NAME}.key ${CERT_FILE_NAME}.key

# Create the admin Kubernetes secret, make sure it does not exist before creating it.
kubectl delete secret $ADMIN_SECRET_NAME --ignore-not-found
kubectl create secret generic $ADMIN_SECRET_NAME \
--from-file=${CERT_FILE_NAME}.crt \
--from-file=${CERT_FILE_NAME}.key \
--from-file=${ROOT_CA_FILE_NAME}.crt \
--dry-run=client -o yaml | kubectl apply -f -
