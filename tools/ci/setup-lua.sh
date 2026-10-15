#!/usr/bin/env bash
# Installs LuaJIT 2.1 (same Lua flavour as BeamNG) and luacheck from source.
# Used by CI; also works on any Linux/macOS/WSL box with git + a C compiler.
# Pinned refs keep CI reproducible; bump deliberately.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
SRC="${SRC:-$(mktemp -d)}"
LUAJIT_REF="${LUAJIT_REF:-v2.1}"
LUACHECK_REF="${LUACHECK_REF:-v1.2.0}"
ARGPARSE_REF="${ARGPARSE_REF:-0.7.1}"
LFS_REF="${LFS_REF:-v1_8_0}"
SUDO=""; [ -w "$PREFIX" ] || SUDO="sudo"

cd "$SRC"
git clone -q --depth 1 --branch "$LUAJIT_REF" https://github.com/LuaJIT/LuaJIT
make -s -C LuaJIT -j"$(nproc 2>/dev/null || echo 2)"
$SUDO make -s -C LuaJIT install PREFIX="$PREFIX"

git clone -q --depth 1 --branch "$LUACHECK_REF" https://github.com/lunarmodules/luacheck
git clone -q --depth 1 --branch "$ARGPARSE_REF" https://github.com/luarocks/argparse
git clone -q --depth 1 --branch "$LFS_REF" https://github.com/lunarmodules/luafilesystem

LUA_SHARE="$PREFIX/share/lua/5.1"; LUA_LIB="$PREFIX/lib/lua/5.1"
$SUDO mkdir -p "$LUA_SHARE" "$LUA_LIB" "$PREFIX/libexec/luacheck"
$SUDO cp -r luacheck/src/luacheck "$LUA_SHARE/"
$SUDO cp argparse/src/argparse.lua "$LUA_SHARE/"
$SUDO cp luacheck/bin/luacheck.lua "$PREFIX/libexec/luacheck/"
INC="$(ls -d "$PREFIX"/include/luajit-2.1 | head -1)"
cc -O2 -shared -fPIC -I"$INC" luafilesystem/src/lfs.c -o lfs.so
$SUDO cp lfs.so "$LUA_LIB/"
printf '#!/bin/sh\nexec luajit "%s/libexec/luacheck/luacheck.lua" "$@"\n' "$PREFIX" | $SUDO tee "$PREFIX/bin/luacheck" >/dev/null
$SUDO chmod +x "$PREFIX/bin/luacheck"

# PREFIX may not be on PATH yet (CI adds it in a later step).
export PATH="$PREFIX/bin:$PATH"
export LUA_PATH="$LUA_SHARE/?.lua;$LUA_SHARE/?/init.lua;${LUA_PATH:-;}"
export LUA_CPATH="$LUA_LIB/?.so;${LUA_CPATH:-;}"
luajit -v
luacheck --version
