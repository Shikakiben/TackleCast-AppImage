#!/bin/sh

set -eu

ARCH=$(uname -m)
export ARCH
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/pixmaps/tacklecast.png
export DESKTOP=/usr/share/applications/tacklecast.desktop
export STARTUPWMCLASS=tacklecast

# Vulkan is mandatory: TackleCast renders only through wgpu/Vulkan
# (src/render.rs: Backends::all(), no OpenGL fallback).
#
# DEPLOY_VULKAN_ALL=1 brings lavapipe (software Vulkan, from vulkan-swrast):
# quick-sharun skips it by default ("libvulkan_lvp.so pulls in LLVM",
# quick-sharun.sh:1334), but libLLVM is already bundled through libgallium, so
# the extra cost is ~2 MiB.
#
# OpenGL is deliberately NOT deployed: with DEPLOY_OPENGL=1 the packaged app
# dies on the first frame with
#   "Conflicting samplers for _group_0_binding_1_fs"
#   "Shader translation error ... A image was used with multiple samplers"
# (the app binds two samplers to one texture, which naga rejects once the
# shipped GL/gallium stack is in play).
#
# Status: the bare binary renders 56 fps, but the packaged run is still not
# validated. In a plain Arch container the renderer init fails with
# "Parent device is lost", i.e. wgpu lands on GL instead of the bundled
# lavapipe. Under investigation through CI (see notes-ia/).
export DEPLOY_VULKAN=1
export DEPLOY_VULKAN_ALL=1

# Deploy dependencies
quick-sharun /usr/bin/tacklecast

# Turn AppDir into AppImage
quick-sharun --make-appimage

# The smoke test renders a synthetic 1080p pattern (no capture card needed) and
# must report a non-zero fps in its log. This is the only reliable signal:
# the exit code of the AppImage wrapper is not one.
quick-sharun --test ./dist/*.AppImage --test-nv12
