from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


class PackageChecks(unittest.TestCase):
    def test_clean_export_packages_without_local_tracks(self):
        root = Path(__file__).resolve().parents[2]
        paths = subprocess.check_output(
            ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root
        ).decode().split('\0')
        with tempfile.TemporaryDirectory(prefix='runnerdonner-package-check-') as temporary:
            clean = Path(temporary)
            for relative in filter(None, paths):
                destination = clean / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / relative, destination)
            self.assertFalse((clean / 'gpx-variants').exists())
            self.assertFalse((clean / 'test2-perturbed.gpx').exists())
            app = clean / 'dist/轨迹控制面板.app'
            app.parent.mkdir()
            shutil.copytree(root / 'dist/轨迹控制面板.app', app, symlinks=True)
            result = subprocess.run(
                [sys.executable, str(clean / 'Scripts/package.py')], cwd=clean,
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with zipfile.ZipFile(clean / 'RunnerDonner.zip') as archive:
                self.assertIsNone(archive.testzip())
                names = archive.namelist()
                self.assertIn('RunnerDonner/轨迹控制面板.app/Contents/MacOS/LocationController', names)
                self.assertIn('RunnerDonner/README.md', names)
                self.assertFalse(any('gpx-variants' in name or 'test2-perturbed.gpx' in name for name in names))


if __name__ == '__main__':
    unittest.main()
