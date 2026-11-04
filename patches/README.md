# Patchs TackleCast-AppImage

Les deux patchs sont **applicatifs** (règle `appimage-workflow.md` §« solutions
officielles d'abord ») : aucun hook quick-sharun ne peut les remplacer, et les deux
sont des correctifs génériques Linux, pas des contournements d'AppImage.

## 0001 — settings et logs en XDG (obligatoire)

`src/settings.rs` et `src/logger.rs` écrivaient `tacklecast_settings.json` et `logs/`
**à côté de l'exécutable**. Dans une AppImage c'est le montage DwarFS en lecture seule,
et un paquet système est root-owned.

**Reproduit, pas supposé** (2026-11-04, conteneur Arch, dossier `chmod a-w`, `su tester`) :

```
failed to initialize logging: Permission denied (os error 13)
```

Les préférences échouaient silencieusement (`Settings::save()` renvoie l'erreur, le log
n'existait pas pour la voir). Après patch, même test : plus d'erreur, log dans
`$XDG_STATE_HOME/tacklecast/logs/`.

Cibles : `$XDG_CONFIG_HOME/tacklecast/tacklecast_settings.json` et
`$XDG_STATE_HOME/tacklecast/logs/`, avec repli `$HOME/.config` / `$HOME/.local/state`,
puis dossier de l'exe si aucun `HOME` (le comportement upstream redevient le dernier
recours). Les builds debug gardent le comportement upstream (`./logs`, `./…settings.json`)
pour ne pas surprendre les développeurs.

## 0002 — icône de fenêtre sous Linux

`src/main.rs` n'appliquait l'icône que dans un bloc `#[cfg(target_os = "windows")]`
(ressource de l'exe). Sous Linux la fenêtre n'avait donc aucune icône (barre des tâches,
Alt-Tab). Le patch ajoute `set_window_icon()` qui décode `assets/icon.png` via la crate
`image` — **déjà une dépendance upstream** (`Cargo.toml`), donc aucun coût ajouté.

`Window::set_window_icon` n'est pas implémenté sur Wayland (limite du protocole, l'icône
vient alors du `.desktop`), un no-op silencieux y est attendu.

## Vérifications faites avant de figer les patchs

- `cargo build --release --locked` OK avec les deux patchs (Rust 1.99.1, FFmpeg 8.1.3).
- `cargo fmt --all --check` OK.
- Test fonctionnel réel : `$XDG_STATE_HOME` et `$XDG_CONFIG_HOME` utilisés, log lisible.
- Test du cas d'échec initial : plus de `Permission denied`.

## Mise à jour amont

Le code patché est petit et stable (pas de logique métier), mais `make-appimage.sh`
vérifie après application que les marqueurs attendus sont présents (`xdg_base_dir`,
`logs_path`, `set_window_icon`) : si upstream réécrit ces zones, le build casse
franchement au lieu de produire une AppImage aux settings cassés.
