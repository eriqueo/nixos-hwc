#!/usr/bin/env python3
import os
import sys
import hashlib

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".m4v", ".wmv"}
DUP_DIR_NAME = "_DUPLICATES"
MIN_YEAR = 1900
MAX_YEAR = 2100

def iter_video_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        if DUP_DIR_NAME in dirnames:
            dirnames.remove(DUP_DIR_NAME)
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext in VIDEO_EXTENSIONS:
                yield os.path.join(dirpath, name)

def sha1_of_file(path, block_size=1024 * 1024):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(block_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()

def valid_year(year_str):
    if len(year_str) == 4 and year_str.isdigit():
        y = int(year_str)
        if MIN_YEAR <= y <= MAX_YEAR:
            return year_str
    return None

def parse_title_year(name):
    name = name.strip()
    if len(name) < 7:
        return None
    if name.endswith(")") and "(" in name:
        idx = name.rfind("(")
        year_candidate = name[idx + 1:-1]
        year = valid_year(year_candidate)
        if year is not None:
            title = name[:idx].rstrip()
            if title:
                return title, year
    return None

def movie_folder_info(dirpath):
    base = os.path.basename(dirpath)
    return parse_title_year(base)

def movie_info_from_name(stem):
    return parse_title_year(stem)

def find_movie_root(dirpath, root):
    dirpath = os.path.abspath(dirpath)
    root = os.path.abspath(root)
    while True:
        if not dirpath.startswith(root):
            return None
        if movie_folder_info(dirpath) is not None:
            return dirpath
        parent = os.path.dirname(dirpath)
        if parent == dirpath:
            return None
        dirpath = parent

def build_sha_index(root):
    sha_to_paths = {}
    for path in iter_video_files(root):
        sha = sha1_of_file(path)
        sha_to_paths.setdefault(sha, []).append(path)
    return sha_to_paths

def report_structure(root):
    root = os.path.abspath(root)
    print("MODE\tDETAIL\tCURRENT_PATH\tSUGGESTED_PATH_OR_INFO")
    for path in iter_video_files(root):
        dirpath = os.path.dirname(path)
        filename = os.path.basename(path)
        stem, ext = os.path.splitext(filename)
        folder_movie = movie_folder_info(dirpath)
        if folder_movie is not None:
            title, year = folder_movie
            expected_name = f"{title} ({year}){ext}"
            if filename != expected_name:
                expected_path = os.path.join(dirpath, expected_name)
                print(f"BAD_NAME\tfile\t{path}\t{expected_path}")
            continue
        movie_root = find_movie_root(dirpath, root)
        if movie_root is not None:
            base = os.path.basename(dirpath).lower()
            if base == "versions":
                root_title, root_year = movie_folder_info(movie_root)
                name_info = movie_info_from_name(stem)
                if name_info == (root_title, root_year):
                    canonical_path = os.path.join(movie_root, f"{root_title} ({root_year}){ext}")
                    if os.path.abspath(path) != os.path.abspath(canonical_path):
                        print(f"LOOSE_FILE\tfile\t{path}\t{canonical_path}")
            continue
        name_info = movie_info_from_name(stem)
        if name_info is not None:
            title, year = name_info
            canonical_dir = os.path.join(root, f"{title} ({year})")
            canonical_path = os.path.join(canonical_dir, f"{title} ({year}){ext}")
            if os.path.abspath(path) != os.path.abspath(canonical_path):
                print(f"LOOSE_FILE\tfile\t{path}\t{canonical_path}")

def fix_structure(root):
    root = os.path.abspath(root)
    renames = []
    moves = []
    for path in iter_video_files(root):
        dirpath = os.path.dirname(path)
        filename = os.path.basename(path)
        stem, ext = os.path.splitext(filename)
        folder_movie = movie_folder_info(dirpath)
        if folder_movie is not None:
            title, year = folder_movie
            expected_name = f"{title} ({year}){ext}"
            if filename != expected_name:
                expected_path = os.path.join(dirpath, expected_name)
                if not os.path.exists(expected_path):
                    renames.append((path, expected_path))
            continue
        movie_root = find_movie_root(dirpath, root)
        if movie_root is not None:
            base = os.path.basename(dirpath).lower()
            if base == "versions":
                root_title, root_year = movie_folder_info(movie_root)
                name_info = movie_info_from_name(stem)
                if name_info == (root_title, root_year):
                    canonical_path = os.path.join(movie_root, f"{root_title} ({root_year}){ext}")
                    if os.path.abspath(path) != os.path.abspath(canonical_path) and not os.path.exists(canonical_path):
                        moves.append((path, movie_root, canonical_path))
            continue
        name_info = movie_info_from_name(stem)
        if name_info is not None:
            title, year = name_info
            canonical_dir = os.path.join(root, f"{title} ({year})")
            canonical_path = os.path.join(canonical_dir, f"{title} ({year}){ext}")
            if os.path.abspath(path) != os.path.abspath(canonical_path) and not os.path.exists(canonical_path):
                moves.append((path, canonical_dir, canonical_path))
    for src, dst in renames:
        os.rename(src, dst)
        sys.stdout.write(f"RENAMED\t{src}\t{dst}\n")
    for src, dst_dir, dst in moves:
        os.makedirs(dst_dir, exist_ok=True)
        os.rename(src, dst)
        sys.stdout.write(f"MOVED\t{src}\t{dst}\n")

def dup_report(root):
    root = os.path.abspath(root)
    print("MODE\tDETAIL\tCURRENT_PATH\tSUGGESTED_PATH_OR_INFO")
    sha_to_paths = build_sha_index(root)
    for sha, paths in sha_to_paths.items():
        if len(paths) > 1:
            kept = paths[0]
            for dup in paths[1:]:
                print(f"DUPLICATE\t{sha}\t{kept}\t{dup}")

def dup_fix(root):
    root = os.path.abspath(root)
    sha_to_paths = build_sha_index(root)
    dup_root = os.path.join(root, DUP_DIR_NAME)
    for sha, paths in sha_to_paths.items():
        if len(paths) <= 1:
            continue
        sizes = [(os.path.getsize(p), p) for p in paths]
        sizes.sort(reverse=True)
        keep = sizes[0][1]
        for _, dup_path in sizes[1:]:
            target_dir = os.path.join(dup_root, sha)
            os.makedirs(target_dir, exist_ok=True)
            target_path = os.path.join(target_dir, os.path.basename(dup_path))
            if not os.path.exists(target_path):
                os.rename(dup_path, target_path)
                sys.stdout.write(f"MOVED_DUPLICATE\t{sha}\t{dup_path}\t{target_path}\n")

def main():
    if len(sys.argv) < 3:
        print("Usage: media_check.py [report|fix|dup-report|dup-fix] ROOT_DIR", file=sys.stderr)
        sys.exit(1)
    mode = sys.argv[1]
    root = sys.argv[2]
    if mode == "report":
        report_structure(root)
    elif mode == "fix":
        fix_structure(root)
    elif mode == "dup-report":
        dup_report(root)
    elif mode == "dup-fix":
        dup_fix(root)
    else:
        print("Unknown mode, use 'report', 'fix', 'dup-report', or 'dup-fix'", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

