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
from wheel.cli import unpack
assert callable(context.tarball)
assert callable(unpack.unpack)
print('supervisor and repaired vendor imports pass')
