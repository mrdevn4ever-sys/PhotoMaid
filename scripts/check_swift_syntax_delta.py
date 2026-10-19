"""Tree-sitter delta check only: this does NOT compile or type-check Swift.

uv run --no-project --python 3.11 --with tree-sitter==0.26.0 \
  --with tree-sitter-swift==0.7.4 python scripts/check_swift_syntax_delta.py
"""
from pathlib import Path
import json
import subprocess
import sys
import tree_sitter
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
BASE = "ca6f81850a0a4032bbf8093f241f99a7584ab4c6"
parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))


def findings(data):
    tree = parser.parse(data)
    nodes = [tree.root_node]
    found = 0
    while nodes:
        node = nodes.pop()
        if node.type == "ERROR" or node.is_missing:
            found += 1
        nodes.extend(node.children)
    return found


def main():
    tracked = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASE], cwd=ROOT, text=True).splitlines()
    baseline = {}
    for name in tracked:
        if name.endswith(".swift"):
            count = findings(subprocess.check_output(["git", "show", f"{BASE}:{name}"], cwd=ROOT))
            if count:
                baseline[name] = count
    paths = [p for area in ["PhotoMaid", "Sources", "Tests", "PhotoMaidTests", "PhotoMaidUITests"]
             for p in (ROOT / area).rglob("*.swift")]
    current = {p.relative_to(ROOT).as_posix(): findings(p.read_bytes()) for p in paths}
    problems = {name: count for name, count in current.items() if count > baseline.get(name, 0)}
    result = {"layer": "tree-sitter syntax delta, NOT Swift compiler", "swift_files": len(paths),
              "baseline_findings": baseline, "current_findings": {k: v for k, v in current.items() if v},
              "new_or_increased_findings": problems, "status": "FAIL" if problems else "PASS"}
    print(json.dumps(result, indent=2))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
