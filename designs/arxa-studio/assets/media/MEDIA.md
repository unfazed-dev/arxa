# Media assets

Example media for the island smoke screens — one free asset per runtime.
Sourced 2026-07-31; every entry is CC0, public-domain, or from a
permissively-licensed vendor repo (MIT/Apache-2.0), captured with its
source URL and hash. Kenney license text: `kenney/KENNEY-LICENSE.txt`.

| file | source URL | author / publisher | licence | sha256 | notes |
|---|---|---|---|---|---|
| `boombox.glb` | https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/BoomBox/glTF-Binary/BoomBox.glb | Microsoft / Khronos glTF-Sample-Models | CC0 1.0 | `84c32a396684d0b329bbe60428f5cb89c5f447356ccf359b0374856653eca331` | 3D model for the three.js / model-viewer screen. Chosen CC0 over Duck (SCEA Shared Source) and DamagedHelmet (CC BY-NC, non-commercial). Starts with `glTF` magic; 10,945,640 bytes. |
| `off_road_car.riv` | https://raw.githubusercontent.com/rive-app/rive-flutter/master/example/assets/off_road_car.riv | Rive (rive-app/rive-flutter example) | MIT | `a2cf7f74416ebc7c1016dd6801d38ea6e80cd936fead3d7b6240a34110fda960` | Rive runtime example asset; has a state machine with inputs. No magic-byte check — proof is the Rive screen's lens run. 34,921 bytes. |
| `lottie_logo.json` | https://raw.githubusercontent.com/airbnb/lottie-ios/master/Tests/Samples/LottieLogo1.json | Airbnb (airbnb/lottie-ios test samples) | Apache-2.0 | `67e8abf1a812770c0e898d91dfb179b50f50745e35ce5fc42e17746949a6b169` | Standard Lottie animation JSON; parses with `json.load`. 56,651 bytes. |
| `dotlottie-demo.lottie` | https://raw.githubusercontent.com/dotlottie/player-component/master/apps/react-player-test/public/test.lottie | dotlottie (dotlottie/player-component test asset) | MIT | `5992f0134cfc0ff07b40cc5603b486470d25ebe5be7c75e0f8f1c66e214ee600` | A `.lottie` is a zip; `unzip -l` shows `manifest.json` + `animations/`. 2,254 bytes. |
| `kenney/tile_0000.png` | https://kenney.nl/media/pages/assets/tiny-dungeon/f8422efb44-1674742415/kenney_tiny-dungeon.zip | Kenney.nl "Tiny Dungeon" | CC0 1.0 | `ebf91e6638d484dc6bdaec5f30e91589252125146b70c2911f11fac7ebe17090` | Extracted from `kenney_tiny-dungeon.zip` (`Tiles/tile_0000.png`). 99 bytes. |
| `kenney/tile_0084.png` | https://kenney.nl/media/pages/assets/tiny-dungeon/f8422efb44-1674742415/kenney_tiny-dungeon.zip | Kenney.nl "Tiny Dungeon" | CC0 1.0 | `b3909f80a29a0f18729f96a90ebe446ecaf26a195da633f2a6c3dd31f660821e` | Extracted from `kenney_tiny-dungeon.zip` (`Tiles/tile_0084.png`). 232 bytes. |
| `kenney/tile_0085.png` | https://kenney.nl/media/pages/assets/tiny-dungeon/f8422efb44-1674742415/kenney_tiny-dungeon.zip | Kenney.nl "Tiny Dungeon" | CC0 1.0 | `377b35acbce5129e8167df1f5d1d0420805990962a37a30f5784b88b81a40ec2` | Extracted from `kenney_tiny-dungeon.zip` (`Tiles/tile_0085.png`). 230 bytes. |
| `kenney/KENNEY-LICENSE.txt` | https://kenney.nl/media/pages/assets/tiny-dungeon/f8422efb44-1674742415/kenney_tiny-dungeon.zip | Kenney.nl "Tiny Dungeon" | CC0 1.0 | — | License text (`License.txt` in the zip, renamed). Confirms CC0; "free to use in personal, educational and commercial projects". 570 bytes. |
