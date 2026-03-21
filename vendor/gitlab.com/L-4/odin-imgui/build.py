import subprocess
from os import path
import os
import shutil
from glob import glob
import typing
import sys
import platform
import random

# ------------------------------------------------------------------------------
# CONFIGURATION (vendored edition — no git fetches)
# ------------------------------------------------------------------------------

# No longer needed — we assume these folders already exist
# git_heads = { ... }           ← removed
# backend_deps = { ... }        ← removed or kept only for reference

# @CONFIGURE: Which backends to build support for
wanted_backends = ["vulkan", "sdl2", "glfw"]

backends = {
    "allegro5":     {"supported": False},
    "android":      {"supported": False},
    "dx9":          {"supported": False, "enabled_on": ["windows"]},
    "dx10":         {"supported": False, "enabled_on": ["windows"]},
    "dx11":         {"supported": True,  "enabled_on": ["windows"]},
    "dx12":         {"supported": False, "enabled_on": ["windows"]},
    "glfw":         {"supported": True,  "deps": ["glfw"]},
    "glut":         {"supported": False},
    "metal":        {"supported": True,  "enabled_on": ["darwin"]},
    "opengl2":      {"supported": False},
    "opengl3":      {"supported": True},
    "osx":          {"supported": False, "enabled_on": ["darwin"]},
    "sdl2":         {"supported": True,  "deps": ["sdl2"]},
    "sdl3":         {"supported": False},
    "sdlrenderer2": {"supported": True,  "deps": ["sdl2"]},
    "sdlrenderer3": {"supported": False},
    "vulkan":       {"supported": True,  "defines": ["VK_NO_PROTOTYPES"], "deps": ["vulkan"]},
    "webgl":        {"supported": True,  "odin": True},
    "wgpu":         {"supported": True,  "odin": True},
    "win32":        {"supported": False, "enabled_on": ["windows"]},
}

# Keep for reference — but paths are now relative
backend_deps_reference = {
    "sdl2":   {"path": "SDL2"},
    "glfw":   {"path": "glfw"},
    "vulkan": {"path": "Vulkan-Headers"},
}

compile_debug = False
build_wasm = False
build_imgui_internal = True

platform_win32_like = platform.system() == "Windows"
platform_unix_like = platform.system() == "Linux" or platform.system() == "Darwin"

# ──────────────────────────────────────────────────────────────────────────────

def assertx(cond: bool, msg: str):
    if not cond:
        print(msg)
        exit(1)

def exec(cmd: typing.List[str], what: str) -> str:
    max_what_len = 40
    short_what = what[:max_what_len - 2] + ".." if len(what) > max_what_len else what
    print(short_what + (" " * (max_what_len - len(short_what))) + "> " + " ".join(cmd))
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8')
    except subprocess.CalledProcessError as e:
        print("=" * 80)
        print("FAILED")
        print("=" * 80)
        print(e.output.decode())
        exit(1)

def exec_vcvars(cmd: typing.List[str], what):
    if platform.system() != "Windows":
        return exec(cmd, what)
    print(f"{what} (via vcvarsall) > " + " ".join(cmd))
    cmd_str = "vcvarsall.bat x64 && " + " ".join(cmd)
    assertx(subprocess.run(cmd_str, shell=True).returncode == 0, f"Failed: {cmd}")

def copy(from_path: str, files: typing.List[str], to_path: str):
    for file in files:
        shutil.copy(path.join(from_path, file), to_path)

def glob_copy(root_dir: str, glob_pattern: str, dest_dir: str):
    real_pattern = path.join(root_dir, glob_pattern)
    the_files = glob(real_pattern)
    results = [path.relpath(p, root_dir) for p in the_files]
    copy(root_dir, results, dest_dir)
    return results

def platform_select(the_options):
    our_platform = platform.system().lower()
    for platforms_str, value in the_options.items():
        if our_platform in [p.strip() for p in platforms_str.lower().split(",")]:
            return value
    assertx(False, f"No match for platform {our_platform} in {the_options}")

def pp(the_path: str) -> str:
    return path.join(*the_path.split("/"))

def map_to_folder(files: typing.List[str], folder: str) -> typing.List[str]:
    return [path.join(folder, f) for f in files]

def has_tool(tool: str) -> bool:
    try:
        subprocess.check_output([tool], stderr=subprocess.DEVNULL)
        return True
    except FileNotFoundError:
        return False
    except:
        return True

def get_platform_imgui_lib_name() -> str:
    system = platform.system().lower()
    machine = platform.machine()
    if machine in ["AMD64", "x86_64"]:
        processor = "x64"
    elif machine == "arm64":
        processor = "arm64"
    else:
        assertx(False, f"Unknown processor: {machine}")
    ext = "lib" if system == "windows" else "a"
    return f"imgui_{system}_{processor}.{ext}"

def did_re_execute() -> bool:
    if platform.system() != "Windows": return False
    if has_tool("cl"): return False
    if "-no_reexecute" in sys.argv: return False
    print("Re-executing with vcvarsall...")
    os.system(f"vcvarsall.bat x64 && {sys.executable} build.py -no_reexecute")
    return True

def compile(backend_deps_names: typing.Set[str], all_sources: typing.List[str], wasm: bool):
    if wasm:
        compile_flags = [
            '-DIMGUI_IMPL_API=extern"C"',
            "-DIMGUI_DISABLE_DEFAULT_SHELL_FUNCTIONS",
            "-DIMGUI_DISABLE_FILE_FUNCTIONS",
            "--target=wasm32", "-mbulk-memory",
            "-fno-exceptions", "-fno-rtti",
            "-fno-threadsafe-statics", "-nostdlib++",
            "-fno-use-cxa-atexit"
        ]
        assertx(has_tool("odin"), "odin not found!")
        root = exec(["odin", "root"], "Get odin root").strip()
        compile_flags += [f"--sysroot={root}/vendor/libc"]
    else:
        compile_flags = platform_select({
            "windows": ['/DIMGUI_IMPL_API=extern"C"'],
            "linux, darwin": ['-DIMGUI_IMPL_API=extern"C"', "-fPIC", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-std=c++11"],
        })

    if compile_debug:
        compile_flags += platform_select({"windows": ["/Od", "/Z7"], "linux, darwin": ["-g", "-O0"]})
    else:
        compile_flags += platform_select({"windows": ["/O2"], "linux, darwin": ["-O3"]})

    if not wasm:
        for backend_name in wanted_backends:
            backend = backends[backend_name]
            if "enabled_on" in backend and platform.system().lower() not in backend["enabled_on"]:
                continue
            if not backend["supported"]:
                print(f"Warning: compiling unsupported backend '{backend_name}'")
            if backend.get("odin"):
                print(f"Note: backend '{backend_name}' is native Odin — skipping C compile")
                continue

            glob_copy("../../imgui/backends", f"imgui_impl_{backend_name}.*", "temp")
            if backend_name in ["osx", "metal"]:
                all_sources.append(f"imgui_impl_{backend_name}.mm")
            else:
                all_sources.append(f"imgui_impl_{backend_name}.cpp")

            if backend_name == "opengl3":
                shutil.copy("../../imgui/backends/imgui_impl_opengl3_loader.h", "temp")

            for define in backend.get("defines", []):
                compile_flags += platform_select({
                    "windows": f"/D{define}",
                    "linux, darwin": f"-D{define}"
                })

        # Include paths for backend deps (vendored)
        for dep in backend_deps_names:
            dep_path = backend_deps_reference[dep]["path"]
            include = path.join("../../../backend_deps", dep_path, "include")
            if platform_win32_like:
                compile_flags += [f"/I{include}"]
            else:
                compile_flags += [f"-I{include}"]

    all_objects = []
    if platform_win32_like:
        all_objects = [f.removesuffix(".cpp") + ".obj" for f in all_sources]
    else:
        for f in all_sources:
            if f.endswith(".cpp"):
                all_objects.append(f.removesuffix(".cpp") + ".o")
            elif f.endswith(".mm"):
                all_objects.append(f.removesuffix(".mm") + ".o")

    os.chdir("temp")

    if platform_win32_like:
        exec_vcvars(["cl"] + compile_flags + ["/c"] + all_sources, "Compiling sources")
    else:
        exec(["clang"] + compile_flags + ["-c"] + all_sources, "Compiling sources")

    os.chdir("..")

    dest_binary = get_platform_imgui_lib_name()

    if wasm:
        os.makedirs("wasm", exist_ok=True)
        copy("temp", all_objects, "wasm")
    elif platform_win32_like:
        exec(["lib", f"/OUT:{dest_binary}"] + map_to_folder(all_objects, "temp"), "Archiving objects")
    else:
        exec(["ar", "rcs", dest_binary] + map_to_folder(all_objects, "temp"), "Archiving objects")

def main():
    assertx(path.isfile("build.py"), "Run from inside the odin-imgui folder")

    if did_re_execute():
        return

    assertx(has_tool("git") is False or True, "git check skipped — vendored mode")  # optional

    if platform.system() != "Windows":
        assertx(has_tool("clang"), "clang not found!")
        assertx(has_tool("ar"), "ar not found!")

    # Assume these are already vendored at these relative locations
    imgui_path       = "../../imgui"
    dear_bindings_path = "../../dear_bindings"

    assertx(path.isdir(imgui_path), f"Missing vendored imgui at {imgui_path}")
    assertx(path.isdir(dear_bindings_path), f"Missing vendored dear_bindings at {dear_bindings_path}")

    # Optional: check backend deps if any backends need them
    backend_deps_names = set()
    for backend_name in wanted_backends:
        for dep in backends[backend_name].get("deps", []):
            backend_deps_names.add(dep)

    for dep in backend_deps_names:
        dep_path = path.join("../../../backend_deps", backend_deps_reference[dep]["path"])
        assertx(path.isdir(dep_path), f"Missing vendored backend dep: {dep_path}")

    shutil.rmtree("temp", ignore_errors=True)
    os.makedirs("temp")

    # Generate bindings
    exec([
        sys.executable,
        pp(f"{dear_bindings_path}/dear_bindings.py"),
        "-o", pp("temp/c_imgui"),
        "--nogeneratedefaultargfunctions",
        "--imconfig-path", pp("imconfig.h"),
        pp(f"{imgui_path}/imgui.h")
    ], "dear_bindings: ImGui")

    if build_imgui_internal:
        exec([
            sys.executable,
            pp(f"{dear_bindings_path}/dear_bindings.py"),
            "-o", pp("temp/c_imgui_internal"),
            "--include", pp(f"{imgui_path}/imgui.h"),
            "--nogeneratedefaultargfunctions",
            "--imconfig-path", pp("imconfig.h"),
            pp(f"{imgui_path}/imgui_internal.h")
        ], "dear_bindings: ImGui Internal")

    # Generate Odin code
    gen_args = [
        sys.executable, "gen_odin.py",
        "--imgui", pp("temp/c_imgui.json"),
        "--imconfig", pp("temp/c_imgui_imconfig.json")
    ]
    if build_imgui_internal:
        gen_args += ["--imgui_internal", pp("temp/c_imgui_internal.json")]
    exec(gen_args, "gen_odin.py")

    # Copy core imgui sources
    glob_copy(imgui_path, "*.h", "temp")
    imgui_sources = glob_copy(imgui_path, "*.cpp", "temp")

    shutil.copy("imconfig.h", "temp/imconfig.h")  # our version overrides

    all_sources = imgui_sources + ["c_imgui.cpp"]
    if build_imgui_internal:
        all_sources.append("c_imgui_internal.cpp")

    # Write enabled.odin
    with open("enabled.odin", "w", encoding="utf-8") as f:
        f.write("package imgui\n\n")
        f.write("// Generated build configuration\n\n")
        f.write(f"DEBUG_ENABLED :: {'true' if compile_debug else 'false'}\n")
        f.write(f"WASM_ENABLED :: {'true' if build_wasm else 'false'}\n\n")
        for b in backends:
            enabled = b in wanted_backends
            f.write(f"BACKEND_{b.upper()}_ENABLED :: {str(enabled).lower()}\n")

    if build_wasm:
        compile(backend_deps_names, all_sources, True)
    compile(backend_deps_names, all_sources, False)

    dest = get_platform_imgui_lib_name()
    expected = ["imgui.odin", "enabled.odin", dest]

    for file in expected:
        assertx(path.isfile(file), f"Missing expected output: {file}")

    print("Build finished (vendored mode)")
    if random.random() < 0.01:
        print("...or did it?")

if __name__ == "__main__":
    main()
