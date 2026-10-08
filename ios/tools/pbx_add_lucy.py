"""Adds Lucy build-1 sources and the LucyCore local package to the Xcode project (idempotent)."""
import sys
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "Edge0PhoneProbe.xcodeproj" / "project.pbxproj"
FILES = ["AssistantPrefs.swift", "AudioSession.swift", "VoiceOutput.swift", "VoiceInput.swift",
         "LucyIntents.swift", "SettingsView.swift", "LockGate.swift", "DevilVoicePlayer.swift"]


def sub(s, anchor, insert, after=True):
    if anchor not in s:
        sys.exit(f"anchor not found: {anchor!r}")
    return s.replace(anchor, anchor + insert if after else insert + anchor, 1)


s = P.read_text(encoding="utf-8")
if "LucyCore" in s:
    print("already patched")
    sys.exit(0)
bf = fr = grp = src = ""
for k, name in enumerate(FILES, 1):
    f, b = f"A0000000000000000000C{k:03d}", f"A0000000000000000000D{k:03d}"
    bf += f"\t\t{b} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {f} /* {name} */; }};\n"
    fr += (f"\t\t{f} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
           f"path = {name}; sourceTree = \"<group>\"; }};\n")
    grp += f"\t\t\t\t{f} /* {name} */,\n"
    src += f"\t\t\t\t{b} /* {name} in Sources */,\n"
bf += ("\t\tA0000000000000000000E103 /* LucyCore in Frameworks */ = {isa = PBXBuildFile; "
       "productRef = A0000000000000000000E102 /* LucyCore */; };\n")
s = sub(s, "/* End PBXBuildFile section */", bf, after=False)
s = sub(s, "/* End PBXFileReference section */", fr, after=False)
s = sub(s, "\t\t\t\tA00000000000000000000012 /* ContentView.swift */,\n", grp)
s = sub(s, "\t\t\t\tA00000000000000000000002 /* ContentView.swift in Sources */,\n", src)
s = sub(s, "\t\t\t\tA00000000000000000000005 /* Edge0MLX in Frameworks */,\n",
        "\t\t\t\tA0000000000000000000E103 /* LucyCore in Frameworks */,\n")
s = sub(s, "\t\t\t\tA00000000000000000000072 /* Edge0MLX */,\n",
        "\t\t\t\tA0000000000000000000E102 /* LucyCore */,\n")
s = sub(s, "\t\t\t\tA00000000000000000000081 /* XCLocalSwiftPackageReference \".\" */,\n",
        "\t\t\t\tA0000000000000000000E101 /* XCLocalSwiftPackageReference \"LucyCore\" */,\n")
s = sub(s, "/* End XCLocalSwiftPackageReference section */",
        "\t\tA0000000000000000000E101 /* XCLocalSwiftPackageReference \"LucyCore\" */ = {\n"
        "\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = LucyCore;\n\t\t};\n", after=False)
s = sub(s, "/* End XCSwiftPackageProductDependency section */",
        "\t\tA0000000000000000000E102 /* LucyCore */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tpackage = A0000000000000000000E101 /* XCLocalSwiftPackageReference \"LucyCore\" */;\n"
        "\t\t\tproductName = LucyCore;\n\t\t};\n", after=False)
P.write_text(s, encoding="utf-8", newline="\n")
print("patched")
