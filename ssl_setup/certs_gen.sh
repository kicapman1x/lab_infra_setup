#!/bin/bash

openssl genrsa -aes-128-cbc -out ca.key 2048

openssl req -x509 -new -nodes -key ca.key -sha256 -days 1825 -out ca.pem 

openssl genrsa -out han.gg.key 2048

openssl req -new -key han.gg.key -out han.gg.csr

openssl x509 -req -in han.gg.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out han.gg.crt -days 1825 -sha256 -extfile han.gg.ext