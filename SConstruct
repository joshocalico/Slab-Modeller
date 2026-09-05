#!/usr/bin/env python
import os

libname = "slab"
projectdir = "project"

if not (os.path.isdir("godot-cpp") and os.listdir("godot-cpp")):
    print("godot-cpp is missing. Run: git submodule update --init --recursive")
    Exit(1)

env = SConscript("godot-cpp/SConstruct")
env.Append(CPPPATH=["src/"])

def fail_if_kernel_includes_classes():
    kernel = "src/kernel"
    if not os.path.isdir(kernel):
        return
    bad = []
    for root, _dirs, files in os.walk(kernel):
        for name in files:
            if not name.endswith((".hpp", ".h", ".cpp")):
                continue
            path = os.path.join(root, name)
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()
            if "godot_cpp/classes/" in text:
                bad.append(path)
    if bad:
        print("kernel must not include godot_cpp/classes/*:")
        for path in bad:
            print(" ", path)
        Exit(1)

fail_if_kernel_includes_classes()

sources = Glob("src/*.cpp") + Glob("src/kernel/*.cpp") + Glob("src/kernel/ops/*.cpp")

if env["platform"] == "macos":
    library = env.SharedLibrary(
        "project/addons/slab/bin/lib{}.{}.{}.framework/lib{}.{}.{}".format(
            libname, env["platform"], env["target"], libname, env["platform"], env["target"]
        ),
        source=sources,
    )
else:
    library = env.SharedLibrary(
        "project/addons/slab/bin/lib{}{}".format(libname, env["suffix"]),
        source=sources,
    )

Default(library)

test_env = env.Clone()
test_env.Append(CPPPATH=["tests/"])
test_sources = Glob("src/kernel/*.cpp") + Glob("src/kernel/ops/*.cpp") + Glob("tests/*.cpp")
test_prog = test_env.Program("bin/slab_kernel_test", test_sources)
Default(test_prog)
