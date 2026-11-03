# Replace only the two vulnerable setuptools-vendored libraries. Keep setuptools
# below 81 because this exact supervisor still consumes pkg_resources.
import importlib.metadata
import pathlib
import shutil
import zipfile

vendor = pathlib.Path('/usr/lib/python3.12/site-packages/setuptools/_vendor')
for path in [vendor / 'jaraco/context.py', vendor / 'wheel', *vendor.glob('jaraco.context-*.dist-info'), *vendor.glob('jaraco_context-*.dist-info'), *vendor.glob('wheel-*.dist-info')]:
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()
for wheel in sorted(pathlib.Path('/tmp/python-vendor').glob('*.whl')):
    with zipfile.ZipFile(wheel) as archive:
        # Fixed-hash wheels; still reject paths outside the declared owner.
        for name in archive.namelist():
            if not (vendor / name).resolve().is_relative_to(vendor):
                raise ValueError('wheel path escapes vendor root')
        archive.extractall(vendor)
import supervisor
import pkg_resources
from jaraco import context
from wheel._commands import unpack
assert callable(context.tarball)
assert callable(unpack.unpack)
# Exercise the fixed wheel unpack path against a synthetic traversal archive.
import base64
import hashlib
import io
import csv
import stat
import tempfile
with tempfile.TemporaryDirectory() as temp:
    root = pathlib.Path(temp)
    sentinel = root / 'sentinel'
    sentinel.write_text('keep')
    sentinel.chmod(0o600)
    payload = b'archive'
    digest = base64.urlsafe_b64encode(hashlib.sha256(payload).digest()).rstrip(b'=').decode()
    record = f'../../sentinel,sha256={digest},{len(payload)}\nprobe-1.dist-info/RECORD,,\n'
    archive_path = root / 'probe-1-py3-none-any.whl'
    with zipfile.ZipFile(archive_path, 'w') as archive:
        info = zipfile.ZipInfo('../../sentinel')
        info.external_attr = (stat.S_IFREG | 0o777) << 16
        archive.writestr(info, payload)
        archive.writestr('probe-1.dist-info/RECORD', record)
    try:
        unpack.unpack(str(archive_path), str(root / 'unpacked'))
    except (ValueError, zipfile.BadZipFile):
        pass
    assert sentinel.read_text() == 'keep'
    assert stat.S_IMODE(sentinel.stat().st_mode) == 0o600
print('supervisor imports and wheel traversal containment pass')
