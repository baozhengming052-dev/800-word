"""Deterministic Tag versions and release assets. No remote writes or local git mutations."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
from string import Template
import subprocess
import sys

TAG = re.compile(r"v([1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)\Z")


def git(root, *args):
    executable = shutil.which("git")
    if executable is None and os.name == "nt":
        executable = r"C:\Program Files\Git\cmd\git.exe"
    result = subprocess.run([executable or "git", *args], cwd=root, capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        raise ValueError("Git 检查失败：" + result.stderr.strip())
    return result.stdout.strip()


def default_versions(root):
    project = (root / "Words800App.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    values = []
    for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        matches = re.findall(r"\b" + key + r"\s*=\s*([0-9.]+);", project)
        if len(matches) != 2 or len(set(matches)) != 1:
            raise ValueError(f"Debug / Release 的 {key} 配置缺失或不一致。")
        values.append(matches[0])
    return tuple(values)


def resolve_version(ref, event, defaults):
    if event not in ("push", "workflow_dispatch"):
        raise ValueError("不支持的工作流事件。")
    if ref.startswith("refs/tags/"):
        tag = ref[len("refs/tags/"):]
        if not TAG.fullmatch(tag):
            raise ValueError("发布 Tag 必须为 vX.Y.Z：X 为1–9999，Y/Z 为0–99，不含前导零或测试版后缀。")
        return {"tag": tag, "version": tag[1:], "build_number": tag[1:], "publish": True}
    if event == "workflow_dispatch" and ref.startswith("refs/heads/"):
        return {"tag": None, "version": defaults[0], "build_number": defaults[1], "publish": False}
    raise ValueError("普通分支推送不发布；请推送 vX.Y.Z Tag，或手动运行测试构建。")


def extract_changelog(markdown, tag):
    """Only real level-three headings inside 更新日志; fenced README examples are ignored."""
    in_log = False
    collecting = False
    fence = None
    sections = []
    current = []
    for line in markdown.splitlines():
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if collecting:
                current.append(line)
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = None
            continue
        if marker:
            fence = marker[1]
            if collecting:
                current.append(line)
            continue
        heading = re.match(r"^(#{1,3})\s+(.+?)\s*#*\s*$", line)
        if heading:
            level, text = len(heading[1]), heading[2]
            if collecting:
                sections.append("\n".join(current).strip())
                current = []
                collecting = False
            if level <= 2:
                in_log = level == 2 and text == "更新日志"
            elif in_log:
                collecting = text == tag
            continue
        if collecting:
            current.append(line)
    if collecting:
        sections.append("\n".join(current).strip())
    if len(sections) > 1:
        raise ValueError(f"README 更新日志中重复出现 {tag}，请只保留一份版本记录。")
    return sections[0] if sections and sections[0] else None


def git_changes(root, tag, base_url):
    current = tuple(map(int, TAG.fullmatch(tag).groups()))
    prior = []
    for value in git(root, "tag", "--merged", "HEAD", "--list", "v*").splitlines():
        match = TAG.fullmatch(value)
        if match and tuple(map(int, match.groups())) < current:
            prior.append(value)
    previous = max(prior, key=lambda value: tuple(map(int, TAG.fullmatch(value).groups()))) if prior else None
    revision = f"{previous}..HEAD" if previous else "HEAD"
    lines = git(root, "log", "--max-count=30", "--format=%h %s", revision, "--").splitlines()
    changes = []
    for line in lines:
        short_sha, _, subject = line.partition(" ")
        # Commit text is content, not markup or instructions; avoid accidental mentions.
        subject = html.escape(subject).replace("@", "&#64;")
        subject = re.sub(r"([\\`*_\[\]])", r"\\\1", subject)
        changes.append(f"- {subject}（`{short_sha}`）")
    if not changes:
        changes = ["- 此 Tag 与上一版本指向相同源码，无新增提交。"]
    description = "此版本未单独填写 README 更新记录，以下内容来自实际 Git 提交（最多30条）：\n\n" + "\n".join(changes)
    if previous:
        description += f"\n\n[完整变更：{previous} → {tag}]({base_url}/compare/{previous}...{tag})"
    return description


def prepare(root, environment):
    ref = environment.get("GITHUB_REF", "")
    metadata = resolve_version(ref, environment.get("GITHUB_EVENT_NAME", ""), default_versions(root))
    repository = environment.get("GITHUB_REPOSITORY", "")
    server = environment.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]+)?", server):
        raise ValueError("GitHub 仓库或服务器地址无效。")
    commit = git(root, "rev-parse", "--verify", "HEAD^{commit}")
    if not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise ValueError("无法识别当前提交。")
    tag = metadata["tag"]
    if tag and git(root, "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}") != commit:
        raise ValueError("Tag 不指向当前构建的提交，已拒绝发布。")
    metadata.update(commit=commit, repository=repository, server_url=server,
                    artifact_label=tag or f"manual-{commit[:12]}")
    base = f"{server}/{repository}"
    if tag:
        changes = extract_changelog((root / "README.md").read_text(encoding="utf-8"), tag)
        metadata["notes_source"] = "README" if changes else "git"
        if not changes:
            changes = git_changes(root, tag, base)
        template = Template((root / ".github/release-template.md").read_text(encoding="utf-8"))
        notes = template.substitute(tag=tag, version=metadata["version"], changes=changes, commit=commit,
                                    commit_url=f"{base}/commit/{commit}",
                                    ipa_url=f"{base}/releases/download/{tag}/Words800App.ipa",
                                    checksum_url=f"{base}/releases/download/{tag}/Words800App.ipa.sha256")
    else:
        metadata["notes_source"] = "preview"
        notes = f"## 手动测试构建\n\n版本：{metadata['version']}；提交：`{commit}`。\n\n此构建不会创建 Release，请在 Actions Artifacts 下载。\n"
    output = root / "build/release"
    output.mkdir(parents=True, exist_ok=True)
    with (output / "release-notes.md").open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(notes.rstrip() + "\n")
    (root / "build/release-metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if environment.get("GITHUB_OUTPUT"):
        with open(environment["GITHUB_OUTPUT"], "a", encoding="utf-8", newline="\n") as stream:
            for key in ("tag", "version", "build_number", "publish", "artifact_label", "commit"):
                value = metadata[key]
                if isinstance(value, bool):
                    value = str(value).lower()
                stream.write(f"{key}={value if value is not None else ''}\n")
    return metadata


def stage(root):
    source = root / "build/800词学习助手.ipa"
    if not source.is_file() or source.stat().st_size == 0:
        raise ValueError("构建 IPA 缺失或为空，不能创建 Release 制品。")
    metadata_path = root / "build/release-metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    directory = root / "build/release"
    if not (directory / "release-notes.md").is_file():
        raise ValueError("Release 更新说明缺失。")
    target = directory / "Words800App.ipa"
    shutil.copyfile(source, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    with (directory / "Words800App.ipa.sha256").open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(f"{digest}  Words800App.ipa\n")
    metadata["ipa_sha256"] = digest
    (directory / "release-metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "stage"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    arguments = parser.parse_args()
    try:
        if arguments.command == "prepare":
            print(json.dumps(prepare(arguments.root.resolve(), os.environ), ensure_ascii=False))
        else:
            stage(arguments.root.resolve())
            print("PASS: Words800App.ipa / SHA256 / release metadata staged")
    except (ValueError, OSError, KeyError) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
