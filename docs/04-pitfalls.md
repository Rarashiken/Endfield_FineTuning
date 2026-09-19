# Pitfalls

Each of these cost real time, and several produced symptoms that pointed somewhere else entirely.

## `cp -a` silently produces an incomplete CrossOver.app

Copying the bundle with `cp -a` dropped files — in one case `ntdll.so` was missing outright. The symptom
was `wineserver` hanging in "Rosetta Runtime Routines," which reads like an ABI or code-signing problem.

**Use `ditto`.** Upstream's `swap-into-crossover.sh` uses `cp -a`; this is a real latent bug there.

## `arch -x86_64` breaks on Command Line Tools

Wrapping the build in `arch -x86_64` gives:

```
xcrun: error: unable to load libxcrun
  (fat file, but missing compatible architecture (have 'arm64,arm64e', need 'x86_64'))
```

The CLT copy of `libxcrun.dylib` has no x86_64 slice. Full Xcode ships a fat one, which is why this is not
universally reported.

**Drop `arch -x86_64` entirely.** `CFLAGS="-arch x86_64"` still defines `__x86_64__` and emits x86_64 code,
while the compiler itself runs natively as arm64 and `xcrun` works. Add
`--build=x86_64-apple-darwin --host=x86_64-apple-darwin` to configure.

## llvm-mingw at the end of `PATH`

With `PATH="...:$PATH:${MW}bin"`, every `.o` compiles fine — the Makefile uses the prefixed
`x86_64-w64-mingw32-gcc`. But `winebuild` invokes a **bare `clang`** when linking PE modules, which resolves
to `/usr/bin/clang`. Apple's clang cannot emit PE, *and* being spawned from an x86_64 `winebuild` it inherits
the x86_64 architecture preference and hits the libxcrun error above.

The result is an hour-long build where the host side fully succeeds and every PE module fails, reporting the
error you thought you had already fixed.

**Put llvm-mingw first.** Safe to do: its `bin/` has no bare `ar`, `nm`, `strip`, `ld` or `objdump`, so only
`clang`/`clang++` are shadowed, and the Makefile's `CC` is an absolute path.

## The `lib64` rpath that source builds do not produce

CodeWeavers' shipped `ntdll.so` carries an rpath that a source build does not:

```
@loader_path/                        <- both
@loader_path/../../../lib64          <- shipped only
```

That is where D3DMetal lives. Swap in a freshly built `ntdll.so` without it and the graphics backend cannot
load its libraries. `winebus.so` similarly needs `@loader_path/../lib64` and `@loader_path/../../../lib64`,
or the `dlopen` of libSDL2 fails.

Add them with `install_name_tool -add_rpath`, then re-sign. Upstream's swap script does not handle this.

## Backups inside the bundle break the signature seal

Keep module backups **outside** `CrossOver-Endfield.app`. A backup directory under
`Contents/SharedSupport/` gets sealed into the re-signed bundle.

Also: re-sign the bundle **without** `--deep`, and give each copied CrossOver a unique
`CFBundleIdentifier`, or LaunchServices collides with the original and Gatekeeper reports the app as damaged.

## `wineserver -k` returns before the registry is flushed

The registry is written when `wineserver` exits, and `-k` is asynchronous. Two distinct failures:

1. **Read-back races the flush.** You write a value, read it back immediately, and see the old one — so the
   change looks like it failed when it actually succeeded.
2. **The dying server overwrites the new value.** Start a new `wine` process too soon after `-k` and the old
   server's exit flush clobbers what you just wrote.

The second is nastier, because running the same commands by hand works — the natural pause between typing
them is enough.

**Wait for the process to actually disappear:**

```bash
kill_wineserver() {
  "$CXR/bin/wineserver" -k >/dev/null 2>&1
  for _ in $(seq 1 15); do pgrep -x wineserver >/dev/null || return 0; sleep 1; done
  echo "warning: wineserver did not exit" >&2
}
```

A related trap, via [soju#42](https://github.com/BCD1210/soju/issues/42): a `winebus` registry change has no
effect until every `wineserver` and `winedevice` for that bottle is gone.

## `winebus` reads its own service key, not `Parameters`

`DriverEntry` uses the driver's `RegistryPath` directly as `driver_key`:

```
HKLM\System\CurrentControlSet\Services\winebus            <- read
HKLM\System\CurrentControlSet\Services\winebus\Parameters <- ignored
```

Values written to `Parameters` — an easy assumption — do nothing at all, silently.

## Always read configuration back

Two rounds of A/B tests were invalidated by writes that appeared to succeed:

- `reg.exe` invoked without `--wait-children` was killed by a following `wineserver -k` before the registry
  flushed, so a `RetinaMode` toggle never landed;
- a Python helper was passed two arguments while reading three, so it died on line 2 with `IndexError` and
  never executed either `re.sub` — while the launcher happily printed the intended setting, because it was
  echoing a shell variable rather than the file.

**Never echo intent. Read the value back from the file and abort on mismatch.** Everything the launcher
configures — graphics backend, msync, NVAPI, Retina mode, pad mode — is verified this way.

## `WINEDEBUG=+seh` and `sample` are not usable here

`+seh` logs every hit of the Rosetta NOP fix: four minutes produced 95 MB and about a million lines, and
crippled performance. `sample` returns an empty call graph for Rosetta-translated processes.
