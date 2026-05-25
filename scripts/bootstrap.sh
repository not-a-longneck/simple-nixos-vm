#!/usr/bin/env bash
curl -sL https://github.com/not-a-longneck/NixOS-VCVM/archive/refs/heads/main.tar.gz | sudo tar -xz -C /etc/nixos --strip-components=1 --overwrite && sudo nixos-rebuild switch
