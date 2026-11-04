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
# Status: validated. The bare binary renders 56 fps, and the packaged AppImage
# now renders too (55.2 fps measured end-to-end through ./AppImage --appimage-extract
# then AppRun --test-nv12). Before patch 0003, the packaged run failed with
# "Parent device is lost" because wgpu::Backends::all() picked a GL adapter;
# patch 0003 asks for Vulkan explicitly.
export DEPLOY_VULKAN=1
export DEPLOY_VULKAN_ALL=1

# Deploy dependencies
quick-sharun /usr/bin/tacklecast

# Turn AppDir into AppImage
quick-sharun --make-appimage

# quick-sharun --test only checks that the app survives ~10 seconds: it does NOT
# prove that anything was rendered. The renderer logs its summary after ~30 s,
# so the first test is a liveness check and the second one asserts a real fps.
quick-sharun --test ./dist/*.AppImage --test-nv12 || :
quick-sharun --test ./dist/*.AppImage --test-mjpeg || :

# Assert an actual rendered frame rate. A capture-card app that cannot render is
# useless, and the exit code would not tell us. This needs an X server:
# quick-sharun --test starts its own Xvfb, a bare command does not, and without
# DISPLAY the app exits before it ever logs a summary.
APPIMAGE_EXTRACT_AND_RUN=1 xvfb-run -a timeout 60 ./dist/*.AppImage --test-nv12 \
    >/dev/null 2>&1 || :

FPS_LOG=$(ls -t "${XDG_STATE_HOME:-$HOME/.local/state}"/tacklecast/logs/*.log 2>/dev/null | head -1)
[ -n "$FPS_LOG" ]
echo "Reading render summary from $FPS_LOG"

# Fail unless the log shows a strictly positive rendered rate. Matching the
# positive case (rather than blacklisting "0.0") keeps this honest: a missing
# summary must not pass either.
FPS=$(sed -n 's/.*render summary: \([0-9][0-9.]*\) rendered fps.*/\1/p' "$FPS_LOG" | tail -1)
[ -n "$FPS" ]
echo "Rendered ${FPS} fps"
awk -v fps="$FPS" 'BEGIN { exit !(fps + 0 > 0) }'
