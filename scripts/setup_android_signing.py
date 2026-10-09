#!/usr/bin/env python3
"""Create one private Android signing identity; optionally install GitHub secrets."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess


def private_write(path: Path, content: str) -> None:
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as output:
        output.write(content)


def create_identity(directory: Path) -> dict[str, str]:
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    config = directory / 'github-signing-secrets.json'
    if config.exists():
        values = json.loads(config.read_text(encoding='utf-8'))
        if not (directory / 'antitourist-release.jks').is_file():
            raise RuntimeError('Existing configuration has no keystore. Restore its backup; do not create a replacement key.')
        return values
    keystore = directory / 'antitourist-release.jks'
    if keystore.exists():
        raise RuntimeError('Keystore already exists. Restore its password configuration; never overwrite it.')
    keytool = shutil.which('keytool')
    if keytool is None:
        raise RuntimeError('Install Java 17 (keytool) before preparing Android signing.')
    password = secrets.token_urlsafe(36)
    values = {'ANDROID_STORE_PASSWORD': password, 'ANDROID_KEY_PASSWORD': password,
              'ANDROID_KEY_ALIAS': 'antitourist'}
    environment = {**os.environ, **values}
    subprocess.run([keytool, '-genkeypair', '-noprompt', '-keystore', str(keystore),
        '-storetype', 'JKS', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-alias', values['ANDROID_KEY_ALIAS'], '-dname', 'CN=AntiTourist Android',
        '-storepass:env', 'ANDROID_STORE_PASSWORD', '-keypass:env', 'ANDROID_KEY_PASSWORD'],
        env=environment, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    keystore.chmod(0o600)
    values['ANDROID_KEYSTORE_BASE64'] = base64.b64encode(keystore.read_bytes()).decode('ascii')
    private_write(config, json.dumps(values, indent=2) + '\n')
    return values


def install_secrets(values: dict[str, str], repository: str) -> None:
    gh = shutil.which('gh')
    if gh is None:
        raise RuntimeError('Install GitHub CLI and run gh auth login, or add the four secrets in repository settings.')
    for name in ['ANDROID_KEYSTORE_BASE64', 'ANDROID_STORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']:
        # A secret is passed on stdin, never in process arguments or output.
        subprocess.run([gh, 'secret', 'set', name, '--repo', repository], input=values[name],
            text=True, check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path.home() / '.antitourist-signing')
    parser.add_argument('--install-secrets', action='store_true')
    parser.add_argument('--repo', default='Levfjodorov/Antitourist')
    args = parser.parse_args()
    directory = args.directory.expanduser().resolve()
    if Path(__file__).resolve().parents[1] == directory or Path(__file__).resolve().parents[1] in directory.parents:
        raise RuntimeError('Keep signing files outside the Git repository.')
    values = create_identity(directory)
    if args.install_secrets:
        install_secrets(values, args.repo)
    print('Signing identity ready. Keep the keystore and password configuration together in a private backup.')
    print('Private directory: ' + str(directory))


if __name__ == '__main__':
    main()
