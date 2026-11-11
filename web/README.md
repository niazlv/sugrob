# Sugrob in the browser

A demo page where the app's own simulation core runs in the browser: the same Swift sources
(`Sim`, `People*`, `Wind`) compiled to WebAssembly, drawn with WebGL2 on top of a mock desktop.

- `build.sh` — copies the core sources next to the bridge and builds `site/sugrob.wasm`.
- `Bridge/Bridge.swift` — what `Overlay.swift` and `App.swift` do in the app: settings, window
  frames → ledges, cursor and mitten, plus the scene setup and the "jobs" for the little people.
- `Bridge/Shim.swift` — stand-ins for the few Foundation calls the core makes.
- `site/` — the static page: `engine.js` (wasm loader), `render.js` (WebGL2 port of the Metal
  shaders), `app.js` (windows, menu bar, Dock), `style.css`, `index.html`.

## Build

Xcode's Swift cannot target WebAssembly. Install the swift.org toolchain and the matching
Swift SDK for WebAssembly (see <https://www.swift.org/documentation/articles/wasm-getting-started.html>),
then:

```bash
./build.sh
```

```bash
python3 -m http.server 8765 --directory site
```

`SUGROB_SWIFT` and `SUGROB_WASM_SDK` override the toolchain path and the SDK name.
