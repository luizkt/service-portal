#!/usr/bin/env python3
"""Mantém o AGENTS.md de um componente em sincronia com o código.

Uso:
  scripts/repo-index.py inventory <dir>   imprime inventário para iniciar um AGENTS.md novo
  scripts/repo-index.py check <dir>       valida AGENTS.md (caminhos, drift, tamanho, orçamento)
  scripts/repo-index.py write <dir>       atualiza os blocos gerados e a data em AGENTS.md

Blocos gerados ficam entre <!-- gen:NOME --> e <!-- /gen:NOME -->. Hoje existe só `size`.
Texto de intenção (responsabilidade, "quero X → onde", armadilhas) é manual e nunca é reescrito.

Código de saída: 0 ok, 1 erro (caminho citado não existe, bloco gerado desatualizado),
2 uso incorreto. Com --strict, avisos (drift, orçamento) também viram erro.
Só usa a biblioteca padrão do Python 3.
"""

import argparse
import fnmatch
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

SOURCE_EXT = {".java", ".kt", ".py", ".ts", ".tsx", ".js", ".go", ".rs", ".cs"}
PATH_EXT = SOURCE_EXT | {".yml", ".yaml", ".xml", ".md", ".kts", ".sh", ".json", ".txt", ".toml"}
BUILD_FILES = {
    "build.gradle.kts", "build.gradle", "pom.xml", "package.json", "pyproject.toml",
    "go.mod", "Cargo.toml", "Dockerfile", "docker-compose.yml", "settings.gradle.kts",
}
ENTRY_NAMES = {"main", "index", "app", "server", "Main", "App"}
DEFAULT_MAX_TOKENS = 3500


def tracked_files(root: Path) -> list[str]:
    """Arquivos versionados dentro de `root`, relativos a `root`."""
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "."],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout
    return sorted(line for line in out.splitlines() if line and "gradle/wrapper/" not in line)


def repo_root(root: Path) -> Path:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], cwd=root, capture_output=True, text=True, check=True
    ).stdout.strip()
    return Path(out)


def count_lines(path: Path) -> int:
    try:
        with path.open("rb") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


def is_source(rel: str, section: str) -> bool:
    return rel.startswith(section + "/") and Path(rel).suffix in SOURCE_EXT


def java_base(files: list[str]) -> str:
    """Diretório base dos pacotes: desce enquanto há um único subdiretório."""
    src = [f for f in files if f.startswith("src/main/") and Path(f).suffix in SOURCE_EXT]
    if not src:
        return ""
    parts = [Path(f).parts for f in src]
    base: list[str] = list(parts[0][:3])  # src/main/<lang>
    while True:
        depth = len(base)
        nxt = {p[depth] for p in parts if len(p) > depth + 1 and list(p[:depth]) == base}
        has_files_here = any(len(p) == depth + 1 and list(p[:depth]) == base for p in parts)
        if len(nxt) == 1 and not has_files_here:
            base.append(nxt.pop())
        else:
            return "/".join(base)


# ───────────────────────── inventory ─────────────────────────


def cmd_inventory(root: Path, _args) -> int:
    files = tracked_files(root)
    print(f"# Inventário: {root.name}\n")
    print("## Build e config")
    for f in files:
        if Path(f).name in BUILD_FILES or re.match(r"src/main/resources/[^/]+\.(ya?ml|properties)$", f):
            print(f"- {f} ({count_lines(root / f)} linhas)")
    print("\n## Possíveis entry points")
    for f in files:
        p = Path(f)
        if f.startswith("src/main/") and p.suffix in SOURCE_EXT and (p.stem.endswith("Application") or p.stem in ENTRY_NAMES):
            print(f"- {f}")
    base = java_base(files)
    print(f"\n## Código por pacote (base: {base or '.'})")
    groups: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for f in files:
        if is_source(f, "src/main"):
            rel = f[len(base) + 1:] if base and f.startswith(base + "/") else f
            pkg = str(Path(rel).parent)
            groups[pkg].append((Path(f).stem, count_lines(root / f)))
    for pkg in sorted(groups):
        items = groups[pkg]
        total = sum(n for _, n in items)
        names = ", ".join(f"{s}({n})" for s, n in sorted(items, key=lambda x: -x[1]))
        print(f"- {pkg}/ [{len(items)} arq, {total} linhas]: {names}")
    main = sum(1 for f in files if is_source(f, "src/main"))
    test = sum(1 for f in files if is_source(f, "src/test"))
    print(f"\n## Tamanho\n- src/main: {main} arquivos de código\n- src/test: {test} arquivos de código")
    exts = Counter(Path(f).suffix for f in files if Path(f).suffix)
    print("- extensões: " + ", ".join(f"{e} {n}" for e, n in exts.most_common(6)))
    print("\n## Bugs recorrentes (candidatos a 'Armadilhas')")
    log = subprocess.run(
        ["git", "log", "--oneline", "-i", "--grep=fix", "-n", "8", "--", "."],
        cwd=root, capture_output=True, text=True,
    ).stdout.strip()
    print(log or "(nenhum commit de fix)")
    return 0


# ───────────────────────── check / write ─────────────────────────


def size_text(root: Path, files: list[str]) -> str:
    ext = Counter(Path(f).suffix for f in files if is_source(f, "src/main"))
    lang = ext.most_common(1)[0][0] if ext else ""
    main = sum(1 for f in files if is_source(f, "src/main"))
    test = sum(1 for f in files if is_source(f, "src/test"))
    return f"Tamanho: {main} arquivos {lang} em `src/main`, {test} em `src/test`."


def expand_braces(token: str) -> list[str]:
    m = re.search(r"\{([^{}]*,[^{}]*)\}", token)
    if not m:
        return [token]
    out: list[str] = []
    for alt in m.group(1).split(","):
        out += expand_braces(token[: m.start()] + alt.strip() + token[m.end():])
    return out


def candidate_paths(text: str) -> set[str]:
    """Spans entre crases que parecem caminho de arquivo."""
    text = re.sub(r"```.*?```", "", text, flags=re.S)  # ignora blocos de código
    text = re.sub(r"<!-- gen:(\w+) -->.*?<!-- /gen:\1 -->", "", text, flags=re.S)  # ignora blocos gerados
    found: set[str] = set()
    for span in re.findall(r"`([^`\n]+)`", text):
        if " " in span or "://" in span or "{{" in span or span.startswith(("/", "@", "-")):
            continue
        if span.startswith("build/") or span.startswith("$"):
            continue
        if re.match(r"^[A-Z]\w*\.[a-z]", span) and Path(span.split("/")[0]).suffix not in PATH_EXT:
            continue  # Classe.metodo
        span = re.sub(r"(?<=\w)\.[a-z]\w*$", lambda m: m.group(0) if m.group(0) in PATH_EXT else "", span) if "/" in span else span
        if "/" not in span and Path(span).suffix not in PATH_EXT:
            continue
        if "/" in span and not re.match(r"^[\w.*\-/{},\[\]]+$", span):
            continue
        found.update(expand_braces(span))
    return found


def resolve(token: str, root: Path, rroot: Path, files: list[str], base: str) -> bool:
    token = token.rstrip("/")
    roots = [root, rroot, root.parent]
    if base:
        roots.append(root / base)
    for r in roots:
        for cand in (token, token + ".java", token + ".kt"):
            if "*" in cand:
                if any(fnmatch.fnmatch(f, cand) for f in tracked_rel(r, root, files)):
                    return True
            elif (r / cand).exists():
                return True
    if "/" not in token:  # só nome de arquivo: procura em qualquer lugar
        return any(Path(f).name == token or fnmatch.fnmatch(Path(f).name, token) for f in files)
    return False


def tracked_rel(r: Path, root: Path, files: list[str]) -> list[str]:
    """Arquivos de `root` relativos a `r` (r é root ou um subdiretório dele)."""
    if r == root:
        return files
    if root in r.parents:
        prefix = str(r.relative_to(root)) + "/"
        return [f[len(prefix):] for f in files if f.startswith(prefix)]
    return []


def uncovered_sources(root: Path, files: list[str], base: str, text: str) -> list[str]:
    cited = candidate_paths(text)
    globs = [t for t in cited if "*" in t]
    cited_stems = {Path(t).stem for t in cited}
    missing = []
    for f in files:
        if not is_source(f, "src/main"):
            continue
        rel = f[len(base) + 1:] if base and f.startswith(base + "/") else f
        if Path(f).stem in text or Path(f).stem in cited_stems:
            continue
        if any(fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(f, g) for g in globs):
            continue
        missing.append(f)
    return missing


GEN_RE = r"(<!-- gen:{name} -->)(.*?)(<!-- /gen:{name} -->)"


def gen_blocks(root: Path, files: list[str]) -> dict[str, str]:
    return {"size": size_text(root, files)}


def apply_gen(text: str, blocks: dict[str, str]) -> str:
    for name, value in blocks.items():
        text = re.sub(GEN_RE.format(name=name), lambda m: f"{m.group(1)}{value}{m.group(3)}", text, flags=re.S)
    return text


def estimate_tokens(text: str) -> int:
    return round(len(text) / 4)


def load_agents(root: Path) -> tuple[Path, str]:
    path = root / "AGENTS.md"
    if not path.exists():
        sys.exit(f"erro: {path} não existe. Use `inventory` para iniciar um.")
    return path, path.read_text(encoding="utf-8")


def cmd_check(root: Path, args) -> int:
    files = tracked_files(root)
    rroot = repo_root(root)
    base = java_base(files)
    _, text = load_agents(root)
    errors: list[str] = []
    warnings: list[str] = []

    for tok in sorted(candidate_paths(text)):
        if not resolve(tok, root, rroot, files, base):
            errors.append(f"caminho citado não existe: {tok}")

    for name, value in gen_blocks(root, files).items():
        m = re.search(GEN_RE.format(name=name), text, flags=re.S)
        if m and m.group(2) != value:
            errors.append(f"bloco gen:{name} desatualizado (rode `write`): esperado «{value}»")
        elif not m:
            warnings.append(f"bloco gen:{name} ausente")

    drift = uncovered_sources(root, files, base, text)
    if drift:
        warnings.append(f"{len(drift)} arquivo(s) de código não citados no AGENTS.md: " + ", ".join(drift[:8]) + (" ..." if len(drift) > 8 else ""))

    tokens = estimate_tokens(text)
    if tokens > args.max_tokens:
        warnings.append(f"AGENTS.md tem ~{tokens} tokens (orçamento {args.max_tokens})")

    print(f"{root.name}: AGENTS.md ~{tokens} tokens, {len(files)} arquivos versionados")
    for w in warnings:
        print(f"  aviso: {w}")
    for e in errors:
        print(f"  ERRO: {e}")
    if errors or (args.strict and warnings):
        return 1
    print("  ok")
    return 0


def cmd_write(root: Path, _args) -> int:
    files = tracked_files(root)
    path, text = load_agents(root)
    new = apply_gen(text, gen_blocks(root, files))
    new = re.sub(r"(atualizado-em: )\d{4}-\d{2}-\d{2}", lambda m: m.group(1) + date.today().isoformat(), new) if new != text else new
    if new == text:
        print(f"{root.name}: sem mudanças")
    else:
        path.write_text(new, encoding="utf-8")
        print(f"{root.name}: AGENTS.md atualizado")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["inventory", "check", "write"])
    ap.add_argument("dir", type=Path)
    ap.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS)
    ap.add_argument("--strict", action="store_true", help="avisos também falham")
    args = ap.parse_args()
    root = args.dir.resolve()
    if not root.is_dir():
        print(f"erro: {root} não é diretório", file=sys.stderr)
        return 2
    return {"inventory": cmd_inventory, "check": cmd_check, "write": cmd_write}[args.command](root, args)


if __name__ == "__main__":
    sys.exit(main())
