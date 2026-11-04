# Patchs TackleCast-AppImage

Les trois patchs sont **applicatifs** (règle `appimage-workflow.md` §« solutions
officielles d'abord ») : aucun hook quick-sharun ne peut les remplacer. Tous sont
aussi de bons candidats de PR upstream, car ils corrigent un comportement fautif
hors AppImage.

Ordre d'application imposé dans `get-dependencies.sh`, avec vérification `grep`
après chaque patch : si upstream réécrit ces zones, le build casse franchement
au lieu de produire une AppImage silencieusement cassée.

## 0001 — settings et logs en XDG (obligatoire)

`src/settings.rs` et `src/logger.rs` écrivaient `tacklecast_settings.json` et
`logs/` **à côté de l'exécutable**. Dans une AppImage c'est le montage DwarFS en
lecture seule, et un paquet système est root-owned.

**Reproduit, pas supposé** (2026-11-04, conteneur Arch, dossier `chmod a-w`, `su tester`) :

```
failed to initialize logging: Permission denied (os error 13)
```

Les préférences échouaient silencieusement (`Settings::save()` renvoie l'erreur,
et le log qui aurait permis de la voir n'existait pas). Après patch, même test :
plus d'erreur, log dans `$XDG_STATE_HOME/tacklecast/logs/`.

Cibles : `$XDG_CONFIG_HOME/tacklecast/tacklecast_settings.json` et
`$XDG_STATE_HOME/tacklecast/logs/`, repli `$HOME/.config` / `$HOME/.local/state`,
puis dossier de l'exe si aucun `HOME`. Les builds debug gardent le comportement
upstream (`./logs`, `./…settings.json`) pour ne pas surprendre les développeurs.

## 0002 — icône de fenêtre sous Linux

`src/main.rs` n'appliquait l'icône que dans un bloc `#[cfg(target_os = "windows")]`
(ressource de l'exe). Sous Linux la fenêtre n'avait donc aucune icône (barre des
tâches, Alt-Tab). Le patch ajoute `set_window_icon()` qui décode `assets/icon.png`
via la crate `image` — **déjà une dépendance upstream**, donc aucun coût ajouté.

No-op attendu sous Wayland (le protocole ne permet pas de définir l'icône ; elle
vient du `.desktop`).

## 0003 — forcer le backend Vulkan (obligatoire pour l'AppImage)

`src/render.rs` demandait `wgpu::Backends::all()` sous Linux, ce qui autorise
wgpu à choisir un adaptateur **GL**. Dans l'AppImage il le choisit, puis échoue :

```
indirect-validation error: ... The selected version doesn't support
Features(BUFFER_STORAGE | COMPUTE_SHADER | DYNAMIC_ARRAY_SIZE)
renderer initialization failed: failed to request device: Parent device is lost
```

Le patch demande `wgpu::Backends::VULKAN`.

**Prouvé par A/B** (même conteneur, même AppImage, une seule variable) :

| Backend | Résultat packagé |
|---|---|
| `Backends::all()` | ❌ `Parent device is lost` |
| `Backends::VULKAN` | ✅ 55,2 fps (`render summary`) |

Et en **CI réelle** (runner GitHub propre) : `Rendered 44.6 fps`, run vert.

C'est le meilleur candidat de PR upstream : TackleCast n'a aucun intérêt à
rendre en GL, et le comportement actuel dépend du hasard de l'environnement.

## Vérifications faites avant de figer les patchs

- Les trois s'appliquent proprement sur un clone vierge du tag `v2.2.0`.
- `cargo build --release --locked` OK avec les trois patchs (Rust 1.99.1, FFmpeg 8.1.3).
- `cargo fmt --all --check` OK.
- Cas d'échec initial 0001 rejoué : plus de `Permission denied`.
- 0003 validé par A/B local **et** par la CI.
