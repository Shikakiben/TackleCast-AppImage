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

## 0003 — demander explicitement le backend Vulkan

`src/render.rs` demande `wgpu::Backends::all()` sous Linux. Le patch remplace ce
`all()` par `wgpu::Backends::VULKAN`. Ce n'est **pas** dire que le code upstream
est faux : en natif il marche. C'est rendre l'empaquetage **reproductible**.

### La chaîne réelle, vérifiée brique par brique

1. Avec `all()`, wgpu essaie GL en plus de Vulkan. Sous X11 le backend GL crée une
   instance EGL, donc le binaire **charge `libEGL.so.1`** au démarrage.
   Mesuré : `file=libEGL.so.1; dynamically loaded by …/cross-libc-dlopen.so`.
2. quick-sharun collecte les `dlopen` en lançant le binaire avec `LD_DEBUG=libs`
   (`Collecting dlopen libraries via LD_DEBUG=libs...`). Il voit donc EGL, GLX,
   GLdispatch et **les embarque** - logs de build : `libEGL.so.1 -> AppDir/lib/…`.
3. Au runtime, EGL est présent dans l'AppDir : wgpu recrée un backend GL. Avec
   `PowerPreference::HighPerformance`, wgpu classe les adaptateurs
   (`wgpu-core/src/instance.rs:377-392`) :

   ```
   DiscreteGpu 1 | IntegratedGpu 2 | Other 3 | VirtualGpu 4 | Cpu 5
   ```

   softpipe (GL) est `Other`=3, lavapipe (Vulkan) est `Cpu`=5. **GL gagne**, et
   wgpu 24 meurt alors sur son propre chemin de validation interne : la feature
   `indirect-validation` est forcée par wgpu (`wgpu/Cargo.toml:145-149`), gardée
   seulement par `INDIRECT_EXECUTION` (`device/resource.rs:221`), que le backend
   GL accorde dès OpenGL 3.1 (`wgpu-hal/src/gles/adapter.rs:483`) alors que la
   validation crée un pipeline compute (4.3).

   Résultat observable : `Parent device is lost`.

En résumé : l'AppImage **s'auto-empoisonne**. L'app charge EGL, l'empaqueteur
l'embarque, et EGL rend le backend GL permanent - donc préféré au Vulkan qui
fonctionne.

### Pourquoi le patch est le bon point de coupe

Un binaire nu ne charge jamais EGL (`readelf -d` : ni libEGL ni libGL) et
n'énumère qu'**un** adaptateur :

```
Instance::new: created Vulkan backend     <- GL absent
Found 1 compatible adapters: llvmpipe (Vulkan)
```

Avec le patch, l'AppImage se comporte comme le binaire nu : GL n'est jamais
demandé, donc jamais chargé, donc jamais déployé. Vérifié sur les logs de build :
`libEGL` apparaît 4 fois dans les builds sans patch, **0 fois** avec.

### Alternative écartée

`DEPLOY_OPENGL=0` ne suffit pas : la collecte `LD_DEBUG` embarque EGL de toute
façon (`quick-sharun.sh:1306` déploie dri/gbm/gallium dès `DEPLOY_VULKAN=1`, et
la collecte ajoute le reste). `WGPU_BACKEND=vulkan` ne fonctionne pas non plus :
wgpu 24 ne lit cette variable que dans `Backends::with_env()`, que l'app n'appelle
pas. Enfin, `CROSS_LIBC_DLOPEN=0` supprimerait la collecte de l'hôte et casserait
les drivers de l'utilisateur.

### Mesures

| Configuration | Résultat |
|---|---|
| binaire nu | 1 adaptateur (Vulkan), rend |
| AppImage sans patch | 2 adaptateurs, GL choisi, `Parent device is lost` |
| AppImage avec patch | GL jamais chargé, 0 lib EGL déployée, rend 44-57 fps |

Validé en CI réelle : run vert avec `Rendered 44.6 fps`.

## Vérifications faites avant de figer les patchs

- Les trois s'appliquent proprement sur un clone vierge du tag `v2.2.0`.
- `cargo build --release --locked` OK avec les trois patchs (Rust 1.99.1, FFmpeg 8.1.3).
- `cargo fmt --all --check` OK.
- Cas d'échec initial 0001 rejoué : plus de `Permission denied`.
- 0003 validé par A/B local **et** par la CI.
