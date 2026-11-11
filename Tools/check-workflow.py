#!/usr/bin/env python3
"""校验 GitHub Actions workflow 的表达式写法。

背景：PyYAML 语法通过 ≠ GitHub 能解析。
GitHub 会在启动阶段拒绝「裸标识符」表达式（例如 ${{ PROJECT_NAME }}），
表现为：run 瞬间 failure、0 个 job、无日志、workflow 名字回退成文件路径。
这类错误只能靠静态规则提前拦住。

用法：python Tools/check-workflow.py [文件...]
"""
import io
import os
import re
import sys

CONTEXTS = {
    "github", "env", "vars", "secrets", "inputs", "needs",
    "strategy", "matrix", "job", "runner", "steps", "workflow",
}
FUNCTIONS = {
    "contains", "startsWith", "endsWith", "format", "join",
    "toJSON", "fromJSON", "hashFiles", "success", "failure",
    "always", "cancelled", "true", "false", "null",
}


def check(path):
    src = io.open(path, encoding="utf-8").read()
    issues = []

    for m in re.finditer(r"\$\{\{(.*?)\}\}", src, re.S):
        expr = m.group(1).strip()
        line = src[:m.start()].count("\n") + 1
        first = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", expr)
        if not first:
            continue
        token = first.group(1)
        if token in CONTEXTS or token in FUNCTIONS:
            continue
        # 整个表达式就是一个裸标识符 → GitHub 会判为 Unrecognized named-value
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expr):
            issues.append(
                f"L{line}: ${{{{ {expr} }}}} 是裸标识符；"
                f"env 变量必须写 ${{{{ env.{expr} }}}}，或直接写字面量"
            )
        else:
            issues.append(f"L{line}: 表达式以未知标识符 '{token}' 开头：{expr[:60]}")

    # 常见结构检查
    for key in ("on:", "jobs:"):
        if key not in src:
            issues.append(f"缺少顶层 {key}")

    if "\t" in src:
        issues.append("YAML 中不能出现 Tab 缩进")

    return issues


def main():
    files = sys.argv[1:] or [".github/workflows/build-ios.yml"]
    failed = False
    for path in files:
        if not os.path.exists(path):
            print(f"跳过（不存在）: {path}")
            continue
        problems = check(path)
        if problems:
            failed = True
            print(f"FAIL {path}")
            for p in problems:
                print("   -", p)
        else:
            print(f"OK   {path}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
