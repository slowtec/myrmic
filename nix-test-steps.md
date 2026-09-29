# Test the fixed flake: CLI with BLE, a cell on Linux and ESP32

Tests the fixed flake on the local branch `nix-support-fixes`, inside Docker. Nothing is installed on your
machine.

Each block says where it runs:

| Label | Where |
|---|---|
| 🖥️ **Host** | a normal terminal on your machine |
| 🐳 **Terminal 1** | the container you start in step 2, inside `nix develop` |
| 🐳 **Terminal 2** | a second shell in the same container (step 8), also inside `nix develop` |

## 1. Clean up old runs

🖥️ **Host**

```sh
docker ps                                  # stop any nix container still running
docker volume rm myrmic-nix myrmic-home
myrmic runtimes stop                       # only if your host myrmic has a runtime running
```

> The container builds its own `myrmic` and keeps its data in the `myrmic-home` volume, so your host `myrmic`
> isn't touched. Don't run a host runtime during the test, and don't add `--network host`, or the two
> versions can join one swarm.

## 2. Start the container

🖥️ **Host**, which becomes **Terminal 1**:

```sh
cd ~/Desktop/peeriot/myrmic-nix-support    # on branch nix-support-fixes
docker run --rm -it --name myrmic-test \
  -e NIX_CONFIG="experimental-features = nix-command flakes" \
  -e CARGO_TARGET_DIR=/root/target \
  -v myrmic-nix:/nix -v myrmic-home:/root -v "$PWD":/src -w /src \
  nixos/nix bash
```

🐳 **Terminal 1**, now inside the container:

```sh
git config --global --add safe.directory /src
nix develop
```

## 3. Build the CLI with BLE

🐳 **Terminal 1**

```sh
cargo install --path swarm/myrmic-cli/ --features ble
export PATH=$HOME/.cargo/bin:$PATH
myrmic --version
```

## 4. Create a cell

🐳 **Terminal 1**

```sh
cd ~ && myrmic new my-cell --sdk /src
```

`--sdk /src` uses the local checkout. Without it, the cell points at this commit on `peeriot/myrmic`, and the
commit only exists on the fork.

## 5. Build the cell for Linux

🐳 **Terminal 1**

```sh
myrmic build ./my-cell
```

## 6. Build the cell for ESP32

🐳 **Terminal 1**. `riscv32imac` needs `wamrc` 2.4.4, which the flake doesn't provide. Build it once:

```sh
[ -d ~/wamr ] || git clone -q --depth 1 -b WAMR-2.4.4 https://github.com/bytecodealliance/wasm-micro-runtime ~/wamr
mkdir -p ~/wamr/core/deps/llvm
ln -sfn "$(nix build --no-link --print-out-paths nixpkgs#llvmPackages_18.llvm.dev)" ~/wamr/core/deps/llvm/build
export PATH="$(nix build --no-link --print-out-paths nixpkgs#ninja)/bin:$PATH"
cmake -S ~/wamr/wamr-compiler -B ~/wamrc-build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build ~/wamrc-build && cp ~/wamrc-build/wamrc ~/.cargo/bin/
wamrc --version                            # wamrc 2.4.4
```

The "Could NOT find FFI/ZLIB/…" lines and compiler warnings are harmless.

🐳 **Terminal 1**

```sh
cd ~ && myrmic build ./my-cell --platform riscv32imac
```

## 7. Build ESP32 firmware

🐳 **Terminal 1**. This is the path that failed before the fix (`cargo +nightly…`):

```sh
myrmic new --firmware=esp32c6 my-node --sdk /src
myrmic build ./my-node
```

## 8. Start a runtime and deploy the cell

🖥️ **Host**, a new terminal, which becomes **Terminal 2**:

```sh
docker exec -it myrmic-test bash
```

🐳 **Terminal 2**. Leave it running; this is where the cell's logs appear:

```sh
cd /src && nix develop -c bash -c 'export PATH=$HOME/.cargo/bin:$PATH; myrmic runtimes start -n dev --tmp'
```

> Keep this as one command. `nix develop` on its own opens a new shell and swallows any lines pasted after it,
> so the runtime never starts.

> The container has no Bluetooth, so a BlueZ/D-Bus warning here is expected.
>
> Both terminals are in the same container, so multicast discovery works. If `myrmic deploy` can't find the
> runtime, check `myrmic runtimes list`, then bypass multicast with `myrmic --connect tcp/127.0.0.1:<port> …`.

🐳 **Terminal 1**

```sh
myrmic deploy ./my-cell
myrmic cells status                        # my-cell is listed, on the dev runtime
```

## 9. Interact with the cell

Run each command in 🐳 **Terminal 1**, then check 🐳 **Terminal 2** for the log line:

| 🐳 Terminal 1 | 🐳 Terminal 2 should log |
|---|---|
| `myrmic send my-cell increment` | `Incremented count to 1` |
| `myrmic send my-cell increment` | `Incremented count to 2` |
| `myrmic send my-cell increment` | `Incremented count to 3` |
| `myrmic send my-cell count` | `Count is 3 (no caller to answer)` |
| `myrmic send my-cell nope` | an error for an unknown command; the cell keeps running |
| `myrmic send my-cell count` | `Count is 3` again, so the state survived the bad command |

Terminal 1 prints only `successfully sent command` each time.

🐳 **Terminal 1**, remove the cell:

```sh
myrmic delete my-cell
myrmic cells status                        # my-cell is gone
myrmic send my-cell count                  # fails: no such cell
```

## 10. Clean up

🐳 **Terminal 2**: press `Ctrl+C` to stop the runtime, then `exit` twice.

🐳 **Terminal 1**: `exit` twice. This leaves `nix develop`, then the container, which `--rm` deletes.

🖥️ **Host**

```sh
docker volume rm myrmic-nix myrmic-home && docker rmi nixos/nix
```

---

**Not covered:** flashing and running on a real ESP32. That needs the board passed into the container
(`--device /dev/ttyACM0`) and `--network host`, so the board can find the runtime.
