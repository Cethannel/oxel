import subprocess
from os import path
import os
import shutil
from glob import glob
import typing
import sys
import platform
import random

# TODO:
# - Make this file never show it's call stack. Call stacks should mean that a child script failed.
# - Add self-documenting build.ini or similar, as to not require anyone to look
#   at this file unless they want to add a new backend.
# - It could be nice to be able to generate into another folder, or just say --copy-into../../my_cool_folder

# @CONFIGURE: Elements must be keys into below table
wanted_backends = ["vulkan", "sdl2"]

# Supported means that an impl bindings file exists, and that it has been tested.
backends = {
    "allegro5":     { "supported": False },
    "android":      { "supported": False },
    "dx9":          { "supported": False, "enabled_on": ["windows"] },
    "dx10":         { "supported": False, "enabled_on": ["windows"] },
    "dx11":         { "supported": True,  "enabled_on": ["windows"] },
    "dx12":         { "supported": False, "enabled_on": ["windows"] },
    "glfw":         { "supported": True,  "deps": ["glfw"] },
    "glut":         { "supported": False },
    "metal":        { "supported": True,  "enabled_on": ["darwin"] },
    "opengl2":      { "supported": False },
    "opengl3":      { "supported": True  },
    "osx":          { "supported": False, "enabled_on": ["darwin"] },
    "sdl2":         { "supported": True,  "deps": ["sdl2"] },
    "sdl3":         { "supported": False },
    "sdlrenderer2": { "supported": True,  "deps": ["sdl2"] },
    "sdlrenderer3": { "supported": False },
    "vulkan":       { "supported": True,  "defines": ["VK_NO_PROTOTYPES"], "deps": ["vulkan"] },
    "webgl":        { "supported": True,  "odin": True },
    "wgpu":         { "supported": True,  "odin": True },
    "win32":        { "supported": False, "enabled_on": ["windows"] },
}

# For reference only (paths are now hardcoded as relative)
backend_deps_reference = {
    "sdl2":   { "path": "libsdl-org/SDL" },
    "glfw":   { "path": "glfw" },
    "vulkan": { "path": "Vulkan-Headers" },
}

# @CONFIGURE:
compile_debug = False

# @CONFIGURE:
build_wasm = False

# @CONFIGURE:
build_imgui_internal = True

platform_win32_like = platform.system() == "Windows"
platform_unix_like = platform.system() == "Linux" or platform.system() == "Darwin"

def assertx(cond: bool, msg: str):
    if not cond:
        print(msg)
        exit(1)

def hashes_are_same_ish(first: str, second: str) -> bool:
    smallest_hash_size = min(len(first), len(second))
    assertx(smallest_hash_size >= 7, "Hashes not long enough to be sure")
    return first[:smallest_hash_size] == second[:smallest_hash_size]

def exec(cmd: typing.List[str], what: str) -> str:
    max_what_len = 40
    if len(what) > max_what_len:
        what = what[:max_what_len - 2] + ".."
    print(what + (" " * (max_what_len - len(what))) + "> " + " ".join(cmd))
    try: return subprocess.check_output(cmd).decode('utf-8')
    except subprocess.CalledProcessError as uh_oh:
        print("=" * 80)
        print("FAILED")
        print("=" * 80)
        print(uh_oh.output.decode())
        exit(1)

def exec_vcvars(cmd: typing.List[str], what):
    max_what_len = 40
    if len(what) > max_what_len:
        what = what[:max_what_len - 2] + ".."
    print(what + (" " * (max_what_len - len(what))) + "> " + " ".join(cmd))
    assertx(subprocess.run(f"vcvarsall.bat x64 && {' '.join(cmd)}", shell=True).returncode == 0, f"Failed to run command '{cmd}'")

def copy(from_path: str, files: typing.List[str], to_path: str):
    for file in files:
        shutil.copy(path.join(from_path, file), to_path)

def glob_copy(root_dir: str, glob_pattern: str, dest_dir: str):
    real_pattern = os.path.join(root_dir, glob_pattern)
    the_files = glob(real_pattern)
    results = [os.path.relpath(p, root_dir) for p in the_files]
    copy(root_dir, results, dest_dir)
    return results

def platform_select(the_options):
    our_platform = platform.system().lower()
    for platforms_string in the_options:
        if platforms_string.lower().find(our_platform) != -1:
            return the_options[platforms_string]
    print(the_options)
    assertx(False, f"Couldn't find active platform ({our_platform}) in the above options!")

def pp(the_path: str) -> str:
    return path.join(*the_path.split("/"))

def map_to_folder(files: typing.List[str], folder: str) -> typing.List[str]:
    return list(map(lambda file: path.join(folder, file), files))

def has_tool(tool: str) -> bool:
    try: subprocess.check_output([tool], stderr=subprocess.DEVNULL)
    except FileNotFoundError: return False
    except: return True
    else: return True

def get_platform_imgui_lib_name() -> str:
    system = platform.system()
    processor = None
    if platform.machine() in ["AMD64", "x86_64"]: processor = "x64"
    if platform.machine() in ["arm64"]:           processor = "arm64"
    binary_ext = "lib" if system == "Windows" else "a"
    assertx(system != "", "System could not be determined")
    assertx(processor is not None, f"Unexpected processor: {platform.machine()}")
    return f'imgui_{system.lower()}_{processor}.{binary_ext}'

def did_re_execute() -> bool:
    if platform.system() != "Windows": return False
    if has_tool("cl"): return False
    if "-no_reexecute" in sys.argv: return False
    print("Re-executing with vcvarsall..")
    os.system("".join(["vcvarsall.bat x64 && ", sys.executable, " build.py -no_reexecute"]))
    return True

def compile(backend_deps_names: typing.Set[str], all_sources: typing.List[str], wasm: bool):
    if wasm:
        compile_flags = ['-DIMGUI_IMPL_API=extern\"C\"', "-DIMGUI_DISABLE_DEFAULT_SHELL_FUNCTIONS", "-DIMGUI_DISABLE_FILE_FUNCTIONS", "--target=wasm32", "-mbulk-memory", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-nostdlib++", "-fno-use-cxa-atexit"]
        assertx(has_tool("odin"), "odin not found!")
        root = exec(["odin", "root"], "Get odin root").strip()
        compile_flags += ["--sysroot=" + root + "/vendor/libc"]
    else:
        compile_flags = platform_select({
            "windows": ['/DIMGUI_IMPL_API=extern\\\"C\\\"'],
            "linux, darwin": ['-DIMGUI_IMPL_API=extern\"C\"', "-fPIC", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-std=c++11"],
        })

    if compile_debug: compile_flags += platform_select({ "windows": ["/Od", "/Z7"], "linux, darwin": ["-g", "-O0"] })
    else: compile_flags += platform_select({ "windows": ["/O2"], "linux, darwin": ["-O3"] })

    if not wasm:
        for backend_name in wanted_backends:
            backend = backends[backend_name]
            if "enabled_on" in backend and not platform.system().lower() in backend["enabled_on"]:
                continue
            if not backend["supported"]:
                print(f"Warning: compiling backend '{backend_name}' which is not officially supported")
            if "odin" in backend and backend["odin"]:
                print(f"Note: backend '{backend_name}' is native Odin code, nothing to compile")
                continue

            glob_copy(pp("../../../github.com/ocornut/imgui/backends"), f"imgui_impl_{backend_name}.*", "temp")

            if backend_name in ["osx", "metal"]: all_sources += [f"imgui_impl_{backend_name}.mm"]
            else:                                all_sources += [f"imgui_impl_{backend_name}.cpp"]

            if backend_name == "opengl3":
                shutil.copy(pp("../../../github.com/ocornut/imgui/backends/imgui_impl_opengl3_loader.h"), "temp")

            for define in backend.get("defines", []): 
                compile_flags += platform_select({ "windows": f"/D{define}", "linux, darwin": f"-D{define}" })

        # Add backend dependency include paths
        for backend_dep in backend_deps_names:
            if backend_dep == "vulkan":
                include_path = "../../../github.com/KhronosGroup/Vulkan-Headers/include"
            else:
                include_path = path.join("../../../github.com", backend_deps_reference[backend_dep]["path"], "include")

            if platform_win32_like:  compile_flags += ["/I" + include_path]
            elif platform_unix_like: compile_flags += ["-I" + include_path]

    all_objects = []
    if platform_win32_like: 
        all_objects += [file.removesuffix(".cpp") + ".obj" for file in all_sources]
    elif platform_unix_like:
        for file in all_sources:
            if file.endswith(".cpp"): all_objects.append(file.removesuffix(".cpp") + ".o")
            elif file.endswith(".mm"): all_objects.append(file.removesuffix(".mm") + ".o")

    os.chdir("temp")

    if platform_win32_like:  exec_vcvars(["cl"] + compile_flags + ["/c"] + all_sources, "Compiling sources")
    elif platform_unix_like: exec(["clang"] + compile_flags + ["-c"] + all_sources, "Compiling sources")

    os.chdir("..")

    dest_binary = get_platform_imgui_lib_name()

    if wasm:
        shutil.rmtree(path="wasm", ignore_errors=True)
        os.mkdir("wasm")
        copy("temp", all_objects, "wasm")
    elif platform_win32_like: exec(["lib", "/OUT:" + dest_binary] + map_to_folder(all_objects, "temp"), "Making library from objects")
    elif platform_unix_like:  exec(["ar", "rcs", dest_binary] + map_to_folder(all_objects, "temp"), "Making library from objects")

def main():
    assertx(path.isfile("build.py"), "You have to run the script from within the repository for now!")

    if did_re_execute(): return

    assertx(has_tool("git") or True, "Git check skipped in vendored mode")  # optional

    if platform.system() == "Windows":
        pass
    else:
        assertx(has_tool("clang"), "clang not found!")
        assertx(has_tool("ar"), "ar not found!")

    # Vendored paths (relative from inside odin-imgui folder)
    imgui_path = "../../../github.com/ocornut/imgui"
    dear_bindings_path = "../../../github.com/dearimgui/dear_bindings"

    assertx(path.isdir(imgui_path), f"Missing vendored imgui at {imgui_path}")
    assertx(path.isdir(dear_bindings_path), f"Missing vendored dear_bindings at {dear_bindings_path}")

    # Collect needed backend deps
    backend_deps_names = set()
    for backend_name in wanted_backends:
        backend = backends[backend_name]
        for dep in backend.get("deps", []):
            backend_deps_names.add(dep)

    for dep in backend_deps_names:
        if dep == "vulkan":
            dep_path = "../../../github.com/KhronosGroup/Vulkan-Headers"
        else:
            dep_path = path.join("../../../github.com", backend_deps_reference.get(dep, {"path": dep})["path"])
        assertx(path.isdir(dep_path), f"Missing vendored backend dep '{dep}' at {dep_path}")

    shutil.rmtree("temp", ignore_errors=True)
    os.mkdir("temp")

    # Generate Odin bindings
    exec([sys.executable, pp(dear_bindings_path + "/dear_bindings.py"), "-o", pp("temp/c_imgui"), "--nogeneratedefaultargfunctions", "--imconfig-path", pp("imconfig.h"), pp(imgui_path + "/imgui.h")], "Running dear_bindings: ImGui")
    if build_imgui_internal:
        exec([sys.executable, pp(dear_bindings_path + "/dear_bindings.py"), "-o", pp("temp/c_imgui_internal"), "--include", pp(imgui_path + "/imgui.h"), "--nogeneratedefaultargfunctions", "--imconfig-path", pp("imconfig.h"), pp(imgui_path + "/imgui_internal.h")], "Running dear_bindings: ImGui Internal")

    # Generate odin bindings from dear_bindings json file
    gen_cmd = [sys.executable, pp("gen_odin.py"), "--imgui", pp("temp/c_imgui.json"), "--imconfig", pp("temp/c_imgui_imconfig.json")]
    if build_imgui_internal:
        gen_cmd += ["--imgui_internal", pp("temp/c_imgui_internal.json")]
    exec(gen_cmd, "Running odin-imgui")

    # Find and copy imgui sources to temp folder
    _imgui_headers = glob_copy(imgui_path, "*.h", "temp")
    imgui_sources = glob_copy(imgui_path, "*.cpp", "temp")

    # We copied `imconfig.h` from imgui, but we have our own. Overwrite the previous one.
    shutil.copy(pp("imconfig.h"), pp("temp/imconfig.h"))

    # Gather sources, defines, includes etc
    all_sources = imgui_sources
    all_sources += ["c_imgui.cpp"]
    if build_imgui_internal:
        all_sources.append("c_imgui_internal.cpp")

    # Write file describing the build configuration.
    with open("enabled.odin", "w") as f:
        f.writelines([
            "package imgui\n",
            "\n",
            "// This is a generated helper file which you can use to know about the build configuration.\n",
            "\n",
        ])
        f.writelines([f"DEBUG_ENABLED :: {'true' if compile_debug else 'false'}\n"])
        f.writelines([f"WASM_ENABLED :: {'true' if build_wasm else 'false'}\n", "\n"])
        for backend_name in backends:
            f.writelines([f"BACKEND_{backend_name.upper()}_ENABLED :: {'true' if backend_name in wanted_backends else 'false'}\n"])

    if build_wasm:
        compile(backend_deps_names, all_sources, True)
    compile(backend_deps_names, all_sources, False)

    dest_binary = get_platform_imgui_lib_name()

    expected_files = ["imgui.odin", "enabled.odin", dest_binary]

    for file in expected_files:
        assertx(path.isfile(file), f"Missing file '{file}' in build folder! Something went wrong..")

    print("Looks like everything went ok!")
    if random.random() < 0.01: print("But looks may deceive..")

if __name__ == "__main__":
    main()
