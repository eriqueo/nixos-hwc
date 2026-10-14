# TEMPORARY: pinned Git leaks anonymous tmp_pack_* downloads on cancellation.
# Remove when unpatched Git passes the cancellation regression below.
# ssh.nix owns SSH settings, not a Git package and its native lifecycle test.
{ pkgs }:
let
  cleanupPatch = pkgs.writeText "git-index-pack-cleanup.patch" ''
    --- a/builtin/index-pack.c
    +++ b/builtin/index-pack.c
    @@ -31,6 +31,7 @@
     #include "run-command.h"
     #include "setup.h"
     #include "strvec.h"
    +#include "tempfile.h"
     
     static const char index_pack_usage[] =
     "git index-pack [-v] [-o <index-file>] [--keep | --keep=<msg>] [--[no-]rev-index] [--verify] [--strict[=<msg-id>=<severity>...]] [--fsck-objects[=<msg-id>=<severity>...]] (<pack-file> | --stdin [--fix-thin] [<pack-file>])";
    @@ -154,6 +155,7 @@
     static uint32_t input_crc32;
     static int input_fd, output_fd;
     static const char *curr_pack;
    +static struct tempfile *pack_tempfile;
     
     /*
      * outgoing_links is guarded by read_mutex, and record_outgoing_links is
    @@ -365,6 +367,7 @@
     			output_fd = odb_mkstemp(the_repository->objects, &tmp_file,
     						"pack/tmp_pack_XXXXXX");
     			pack_name = strbuf_detach(&tmp_file, NULL);
    +			pack_tempfile = register_tempfile(pack_name);
     		} else {
     			output_fd = xopen(pack_name, O_CREAT|O_EXCL|O_RDWR, 0600);
     		}
    @@ -1632,6 +1635,7 @@
     
     	rename_tmp_packfile(&final_pack_name, curr_pack_name, &pack_name,
     			    hash, "pack", from_stdin);
    +	delete_tempfile(&pack_tempfile);
     	if (curr_rev_index_name)
     		rename_tmp_packfile(&final_rev_index_name, curr_rev_index_name,
     				    &rev_index_name, hash, "rev", 1);
  '';
  regression = pkgs.writeText "git-pack-cleanup.py" ''
    import os
    from pathlib import Path
    import random
    import signal
    import subprocess
    import sys
    import tempfile
    import time

    binary = sys.argv[1]
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    children = []

    def git(repo, *args, data=None, check=True):
        return subprocess.run([binary, "--git-dir", str(repo), *args],
                              input=data, capture_output=True, env=env, check=check)

    def partial(repo, pack):
        before = set((repo / "objects/pack").glob("tmp_pack_*"))
        child = subprocess.Popen([binary, "--git-dir", str(repo), "index-pack", "--stdin"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, env=env, start_new_session=True)
        children.append(child)
        child.stdin.write(pack[:2 * 1024 * 1024])
        child.stdin.flush()
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            created = set((repo / "objects/pack").glob("tmp_pack_*")) - before
            if len(created) == 1:
                path = created.pop()
                if path.stat().st_size >= 1024 * 1024:
                    return child, path
            if child.poll() is not None:
                raise RuntimeError("index-pack exited before cancellation seam")
            time.sleep(0.002)
        raise RuntimeError("index-pack never reached cancellation seam")

    def cancel(child):
        os.killpg(child.pid, signal.SIGTERM)
        child.stdin.close()
        child.stdin = None
        child.communicate(timeout=10)

    with tempfile.TemporaryDirectory(prefix="git-pack-cleanup-") as directory:
        root = Path(directory)
        try:
            for algorithm in ("sha1", "sha256"):
                source = root / (algorithm + "-source.git")
                target = root / (algorithm + "-target.git")
                for repo in (source, target):
                    git(repo, "init", "--bare", "--object-format=" + algorithm, str(repo))
                oid = git(source, "hash-object", "-w", "--stdin",
                          data=random.Random(42).randbytes(8 * 1024 * 1024)).stdout.strip()
                pack = git(source, "pack-objects", "--stdout", data=oid + b"\n").stdout
                for _ in range(3):
                    child, path = partial(target, pack)
                    cancel(child)
                    assert not path.exists(), "SIGTERM leaked own pack"
                failed = git(target, "index-pack", "--stdin",
                             data=pack[:2 * 1024 * 1024], check=False)
                assert failed.returncode != 0
                assert not list((target / "objects/pack").glob("tmp_pack_*")), "EOF leaked pack"
                first, first_path = partial(target, pack)
                second, second_path = partial(target, pack)
                cancel(first)
                assert not first_path.exists(), "first writer leaked pack"
                assert second_path.exists() and second.poll() is None, "other writer deleted"
                cancel(second)
                assert not second_path.exists(), "second writer leaked pack"
                git(target, "index-pack", "--stdin", data=pack)
                assert git(target, "cat-file", "-t", oid.decode()).stdout.strip() == b"blob"
                git(target, "fsck", "--no-dangling")
                named = target / "caller.pack"
                git(target, "index-pack", "--stdin", str(named), data=pack)
                assert named.exists(), "caller-named pack deleted"
                assert not list((target / "objects/pack").glob("tmp_pack_*"))
                print(algorithm + ": cancellation, EOF, concurrency, success and explicit output pass")
        finally:
            for child in children:
                if child.poll() is None:
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
  '';
in
pkgs.git.overrideAttrs (old: {
  patches = (old.patches or []) ++ [ cleanupPatch ];
  doInstallCheck = true;
  installCheckFlags = (old.installCheckFlags or []) ++ [ "T=t5302-pack-index.sh" ];
  postInstallCheck = (old.postInstallCheck or "") + ''
    ${pkgs.python3}/bin/python ${regression} "$out/bin/git"
  '';
})
