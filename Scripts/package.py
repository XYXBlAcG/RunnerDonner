from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='runnerdonner-delivery-') as temporary:
    temporary = Path(temporary)
    delivery = temporary / 'RunnerDonner'
    delivery.mkdir()
    shutil.copytree(root / 'dist/轨迹控制面板.app', delivery / '轨迹控制面板.app', symlinks=True)
    for name in ('LocationController', 'Scripts', 'docs', 'gpx-variants'):
        shutil.copytree(root / name, delivery / name, symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '.DS_Store'))
    backend = delivery / 'Backend'
    backend.mkdir()
    for source in (root / 'Backend').iterdir():
        if source.is_file() and source.suffix in ('.py', '.zsh', '.txt'):
            shutil.copy2(source, backend / source.name)
    for name in ('tests', 'licenses'):
        shutil.copytree(root / 'Backend' / name, backend / name, ignore=shutil.ignore_patterns('__pycache__'))
    for name in ('使用说明.md', '第三方项目说明.md'):
        shutil.copy2(root / name, delivery / name)
    archive_path = temporary / 'RunnerDonner.zip'
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for source in sorted(delivery.rglob('*')):
            name = source.relative_to(temporary).as_posix()
            if source.is_symlink():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = source.lstat().st_mode << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, os.readlink(source).encode('utf-8'))
            else:
                archive.write(source, name)
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None
        assert 'RunnerDonner/docs/验收.md' in archive.namelist()
        assert not any('/.venv/' in name or '/.tmp/' in name for name in archive.namelist())
    unpacked = temporary / 'unpacked'
    subprocess.run(['ditto', '-x', '-k', str(archive_path), str(unpacked)], check=True)
    subprocess.run([sys.executable, str(root / 'Scripts/check-package.py'), str(unpacked / 'RunnerDonner/轨迹控制面板.app')], check=True)
    shutil.copy2(archive_path, root / 'RunnerDonner.zip')
print(root / 'RunnerDonner.zip')
