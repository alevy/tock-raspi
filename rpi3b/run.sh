#!/bin/sh

qemu-system-aarch64 \
  \
  -M raspi3b \
  -smp 4 \
  -serial null \
  -serial stdio \
  -display none \
  -kernel $1
