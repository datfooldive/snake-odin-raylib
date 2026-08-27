# Snake Odin Raylib

Arcade Snake game built with [Odin](https://odin-lang.org/) and [raylib](https://www.raylib.com/). Play solo or race a pathfinding AI rival.

**[Play the web demo](https://datfooldive.github.io/snake-odin-raylib/)**

## Controls

- **Arrow keys** — move
- **Q** — slow time
- **E** — phase through walls
- **Esc** — pause/resume
- **R** — restart from pause or game over

Main menu includes Single, Versus AI, and BGM/SFX settings.

## Build

Requires Odin and raylib vendor bindings included with Odin.

```sh
./build_desktop.sh
./build/desktop/snake
```

Web build also requires Emscripten:

```sh
./build_web.sh
```

Output: `build/web/index.html`.

## License

[MIT](LICENSE) © 2026 datfooldive
