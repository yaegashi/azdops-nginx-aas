#!/usr/bin/env bash
 
 set -e
 
 version=${_BUILD_ARG_version:-"latest"}
 
 if [ "$version" = "latest" ]; then
     version=$(curl -s https://api.github.com/repos/go-acme/lego/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
 fi
 
 url="https://github.com/go-acme/lego/releases/download/${version}/lego_${version}_linux_amd64.tar.gz"
 
 echo "Installing lego $version from $url"
 curl -sL $url | tar -C /usr/local/bin -xzf - lego
 echo "lego installation complete."