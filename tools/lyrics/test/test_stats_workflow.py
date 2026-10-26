"""実際の workflow の保存手順をローカル Git リモートで検証する。"""
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

WORKFLOW = Path(__file__).resolve().parents[3] / '.github/workflows/lyrics-request-stats.yml'


def step(name):
    source = WORKFLOW.read_text()
    body = source.split('      - name: ' + name + '\n', 1)[1]
    body = body.split('\n      - ', 1)[0]
    return textwrap.dedent(body.split('        run: |\n', 1)[1])


class TestStatsArchive(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.remote = self.root / 'remote.git'
        self.source = self.root / 'source'
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME='test', GIT_AUTHOR_EMAIL='test@example.com',
                        GIT_COMMITTER_NAME='test', GIT_COMMITTER_EMAIL='test@example.com')
        self.run_git('init', '--bare', str(self.remote))
        self.run_git('init', str(self.source))
        (self.source / 'data/lyrics_requests').mkdir(parents=True)
        (self.source / 'data/lyrics_requests/README.md').write_text('archive\n')
        self.run_git('-C', str(self.source), 'add', 'data/lyrics_requests/README.md')
        self.run_git('-C', str(self.source), 'commit', '-m', 'initial')
        self.run_git('-C', str(self.source), 'remote', 'add', 'origin', str(self.remote))
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('#!/bin/sh\n[ "$1 $2" = "auth setup-git" ]\n')
        gh.chmod(0o755)
        self.env['PATH'] = str(bin_dir) + os.pathsep + self.env['PATH']

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *args):
        return subprocess.check_output(['git', *args], env=self.env, stderr=subprocess.DEVNULL,
                                       text=True).strip()

    def shell(self, name, check=True):
        return subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', step(name)],
                              cwd=self.source, env=self.env, capture_output=True, text=True,
                              check=check)

    def open_archive(self, number):
        runner = self.root / ('runner%d' % number)
        runner.mkdir()
        self.env['RUNNER_TEMP'] = str(runner)
        self.shell('Open stats archive')
        return runner / 'lyrics-stats/data/lyrics_requests'

    def test_new_zero_day_is_saved_and_history_accumulates(self):
        archive = self.open_archive(1)
        (archive / '2026-10-24.tsv').write_text('song_id\tcount\n')
        self.shell('Commit if changed')
        first = self.run_git('--git-dir', str(self.remote), 'rev-parse', 'bot/lyrics-stats')
        archive = self.open_archive(2)
        self.assertTrue((archive / '2026-10-24.tsv').exists())
        (archive / '2026-10-25.tsv').write_text('song_id\tcount\na\t3\n')
        self.shell('Commit if changed')
        parent = self.run_git('--git-dir', str(self.remote), 'rev-parse', 'bot/lyrics-stats^')
        self.assertEqual(parent, first)
        head = self.run_git('--git-dir', str(self.remote), 'rev-parse', 'bot/lyrics-stats')
        self.shell('Commit if changed')
        self.assertEqual(self.run_git('--git-dir', str(self.remote), 'rev-parse', 'bot/lyrics-stats'), head)

    def test_failed_remote_does_not_reset_archive(self):
        runner = self.root / 'runner'
        runner.mkdir()
        self.env['RUNNER_TEMP'] = str(runner)
        self.run_git('-C', str(self.source), 'remote', 'set-url', 'origin', str(self.root / 'absent'))
        result = self.shell('Open stats archive', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((runner / 'lyrics-stats').exists())

    def test_missing_secret_fails(self):
        self.env['CLOUDFLARE_OBSERVABILITY_TOKEN'] = ''
        self.assertNotEqual(self.shell('Check secret', check=False).returncode, 0)
