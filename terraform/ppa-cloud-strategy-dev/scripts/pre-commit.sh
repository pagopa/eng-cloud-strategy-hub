#!/bin/bash
TAG=v1.99.2@sha256:34f6cef8b944d571ea22be316a960d8353fcc0571adea35302cbd9ab80bf2758
docker run -v "$(pwd):/lint" -v "$HOME/.terraform.d:$HOME/.terraform.d" -w /lint ghcr.io/antonbabenko/pre-commit-terraform:$TAG run -a --show-diff-on-failure
