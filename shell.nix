# Licensed under the Apache License, Version 2.0 or the MIT License.
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright Tock Contributors 2024.

{ pkgs ? import <nixpkgs> {} }:

with builtins;
let
  inherit (pkgs) stdenv lib;
in
  pkgs.mkShell {
    name = "tock-dev";

    buildInputs = with pkgs; [
      # --- Toolchains ---
      rustup
      cargo-binutils

      # --- Emulator ---
      qemu
    ];

    LD_LIBRARY_PATH="${stdenv.cc.cc.lib}/lib64:$LD_LIBRARY_PATH";

    # The defaults "objcopy" and "objdump" are wrong (stem from the standard
    # environment for x86), use "llvm-obj{copy,dump}" as defined in the makefile
    shellHook = ''
      unset OBJCOPY
      unset OBJDUMP
    '';
  }
