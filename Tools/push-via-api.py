#!/usr/bin/env python3
"""当 github.com 的 git HTTPS 传输不可达、但 api.github.com 可达时，
用 GitHub Git Data API 把本地改动推成远程的一个 commit。

用法：
  python Tools/push-via-api.py <token> [owner/repo] [branch]

原理：
  1. 取远程分支 sha
  2. git diff <远程sha>..HEAD 得到需要变更的文件
  3. 每个文件 POST /git/blobs，POST /git/trees（带 base_tree），
     POST /git/commits，PATCH /git/refs/heads/<branch>
  4. 推 main 会自动触发 Actions 构建

注意：服务端生成的 commit sha 与本地不同（author 时间戳由服务端决定），
      因此本地与远程会分叉；后续继续用本工具以「远程 sha 为基线」推差异即可。
"""
import base64
import json
import subprocess
import sys

API = "https://api.github.com"


def git(*args):
    return subprocess.check_output(["git", *args]).decode("utf-8").strip()


def api(token, method, path, payload=None):
    url = f"{API}{path}"
    cmd = [
        "curl", "-s", "-m", "60", "-X", method,
        "-H", f"Authorization: Bearer {token}",
        "-H", "Accept: application/vnd.github+json",
        "-H", "Content-Type: application/json",
    ]
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        cmd += ["-d", "@-"]
    cmd.append(url)
    r = subprocess.run(cmd, input=data, stdout=subprocess.PIPE)
    try:
        return json.loads(r.stdout.decode("utf-8"))
    except Exception:
        return {"raw": r.stdout.decode("utf-8", errors="replace")[:400]}


def main():
    token = sys.argv[1] if len(sys.argv) > 1 else ""
    repo = sys.argv[2] if len(sys.argv) > 2 else "lzcmm/FamilyWardrobe"
    branch = sys.argv[3] if len(sys.argv) > 3 else "main"
    if not token:
        print("用法: python Tools/push-via-api.py <token> [owner/repo] [branch]")
        return 1

    base = f"/repos/{repo}"

    # 1. 远程基线
    ref = api(token, "GET", f"{base}/git/ref/heads/{branch}")
    if "object" not in ref:
        print("❌ 取远程 ref 失败:", ref)
        return 1
    remote_sha = ref["object"]["sha"]
    print(f"远程 {branch}: {remote_sha}")

    commit = api(token, "GET", f"{base}/git/commits/{remote_sha}")
    if "tree" not in commit:
        print("❌ 取远程 commit 失败:", commit)
        return 1
    base_tree = commit["tree"]["sha"]
    print(f"基线 tree: {base_tree[:8]}")

    # 2. 逐文件比对：远程 tree（recursive）里的 blob sha vs 本地 git hash-object。
    #    不用 git diff <远程sha>..HEAD —— 本地通常没有服务端生成的那个 commit 对象。
    tree_info = api(token, "GET", f"{base}/git/trees/{base_tree}?recursive=1")
    if "tree" not in tree_info:
        print("❌ 取远程 tree 失败:", tree_info)
        return 1
    if tree_info.get("truncated"):
        print("❌ 远程 tree 被截断，文件过多，本工具不适用")
        return 1
    remote_files = {
        e["path"]: e.get("sha")
        for e in tree_info["tree"] if e["type"] == "blob"
    }

    # -z 用 NUL 分隔，避免 core.quotePath 把中文文件名转成八进制转义
    raw_paths = subprocess.check_output(["git", "ls-files", "-z"])
    local_paths = [
        p.decode("utf-8") for p in raw_paths.split(b"\0") if p.strip()
    ]
    local_files = {p: git("hash-object", p) for p in local_paths}

    changed = [p for p in local_paths if remote_files.get(p) != local_files[p]]
    deleted = [p for p in remote_files if p not in local_files]
    if not changed and not deleted:
        print("本地与远程内容一致，没有需要推送的差异")
        return 0
    print(f"待推送: 变更 {len(changed)} 个 / 删除 {len(deleted)} 个")
    for p in changed:
        print(f"   M  {p}")
    for p in deleted:
        print(f"   D  {p}")

    # 3. 上传变更文件的 blobs
    tree_entries = [
        {"path": p, "mode": "100644", "type": "blob", "sha": None}
        for p in deleted
    ]
    for path in changed:
        with open(path, "rb") as f:
            content = f.read()
        blob = api(token, "POST", f"{base}/git/blobs", {
            "content": base64.b64encode(content).decode("ascii"),
            "encoding": "base64",
        })
        if "sha" not in blob:
            print(f"❌ blob 上传失败 {path}:", blob)
            return 1
        mode = git("ls-files", "-s", path).split()[0]
        tree_entries.append({"path": path, "mode": mode, "type": "blob", "sha": blob["sha"]})
        print(f"   blob {path} -> {blob['sha'][:8]}")

    # 4. 新 tree
    tree = api(token, "POST", f"{base}/git/trees", {
        "base_tree": base_tree,
        "tree": tree_entries,
    })
    if "sha" not in tree:
        print("❌ 创建 tree 失败:", tree)
        return 1
    print(f"新 tree: {tree['sha'][:8]}")

    # 5. 新 commit（message 取本地 HEAD 标题，不依赖与远程的父子关系）
    message = git("log", "-1", "--format=%s") or "Update via Git Data API"
    new_commit = api(token, "POST", f"{base}/git/commits", {
        "message": message,
        "tree": tree["sha"],
        "parents": [remote_sha],
    })
    if "sha" not in new_commit:
        print("❌ 创建 commit 失败:", new_commit)
        return 1
    print(f"新 commit: {new_commit['sha'][:8]}")

    # 6. 更新 ref
    patched = api(token, "PATCH", f"{base}/git/refs/heads/{branch}", {
        "sha": new_commit["sha"], "force": False,
    })
    if patched.get("object", {}).get("sha") != new_commit["sha"]:
        print("❌ 更新 ref 失败:", patched)
        return 1

    print()
    print("✅ 推送完成")
    print(f"   https://github.com/{repo}/commits/{branch}")
    print(f"   https://github.com/{repo}/actions")
    print("   推 main 会自动触发一次构建")
    return 0


if __name__ == "__main__":
    sys.exit(main())
