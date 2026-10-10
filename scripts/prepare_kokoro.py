#!/usr/bin/env python3
"""Fetch pinned build-time assets. SenLearn never downloads models at runtime."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / 'Models/kokoro.lock.json'

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): digest.update(chunk)
    return digest.hexdigest()

def contained(root, member):
    target = (root / member).resolve()
    if root.resolve() not in target.parents and target != root.resolve():
        raise ValueError(f'Archive path escapes destination: {member}')

def unpack(archive, destination):
    if archive.suffix == '.zip':
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                contained(destination, member.filename)
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Unexpected symbolic link in runtime archive')
            bundle.extractall(destination)
    else:
        with tarfile.open(archive) as bundle:
            for member in bundle.getmembers():
                contained(destination, member.name)
                if not (member.isfile() or member.isdir()):
                    raise ValueError(f'Unexpected non-regular archive entry: {member.name}')
            bundle.extractall(destination)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-directory', type=Path, default=ROOT / 'build/KokoroDownloads')
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text())
    args.cache_directory.mkdir(parents=True, exist_ok=True)
    def fetch(asset):
        archive = args.cache_directory / asset['archive']
        if not archive.exists() or sha256(archive) != asset['sha256']:
            temporary = archive.with_suffix(archive.suffix + '.partial')
            print(f"Downloading {asset['name']}…", flush=True)
            try:
                with urllib.request.urlopen(asset['url'], timeout=60) as response, temporary.open('wb') as output:
                    shutil.copyfileobj(response, output, length=1024 * 1024)
                if sha256(temporary) != asset['sha256']: raise ValueError(f"Checksum mismatch: {asset['name']}")
                temporary.replace(archive)
            finally:
                temporary.unlink(missing_ok=True)
        print(f"Verified {asset['name']}", flush=True)
        return asset, archive
    # No installed asset is touched until every download has passed its checksum.
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        archives = list(pool.map(fetch, lock['assets']))
    with tempfile.TemporaryDirectory(prefix='SenLearn-Kokoro-') as workspace:
        temporary_root = Path(workspace)
        replacements = []
        for asset, archive in archives:
            extract = temporary_root / asset['name']; extract.mkdir()
            unpack(archive, extract)
            source = extract / asset['extractedPath']
            destination = ROOT / asset['destination']
            if not source.is_dir(): raise ValueError(f"Missing extracted resource: {source}")
            replacements.append((source, destination))
        for source, destination in replacements:
            destination.parent.mkdir(parents=True, exist_ok=True)
            incoming = destination.with_name(destination.name + '.incoming')
            if incoming.exists(): shutil.rmtree(incoming)
            shutil.copytree(source, incoming)
            if destination.exists(): shutil.rmtree(destination)
            incoming.replace(destination)
    model = ROOT / 'Models/Kokoro'
    for name in lock['requiredFiles']:
        if not (model / name).is_file(): raise ValueError(f'Missing model file: {name}')
    (model / 'SenLearn-model.json').write_text(json.dumps({
        'name': lock['model'], 'archiveSHA256': lock['assets'][0]['sha256'],
        'voices': lock['voices'], 'runtime': lock['runtime']
    }, ensure_ascii=False, indent=2) + '\n')
    print('Kokoro resources ready. Open SenLearn.xcodeproj and run; no runtime download is needed.')

if __name__ == '__main__': main()
