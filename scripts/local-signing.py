#!/usr/bin/env python3
"""One-time, user-scoped development signing. No system/TLS trust changes."""
import argparse,contextlib,json,os,pathlib,secrets,shlex,shutil,subprocess,tempfile
STATE=pathlib.Path.home()/'Library/Application Support/JustVibeRemoteSigning'
CONFIG=STATE/'identity.json'
def run(args,secret='',timeout=45):
    try:
        result=subprocess.run([str(a) for a in args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError('macOS authorization did not finish in time. Retry setup when ready to approve the system dialog; no password or command arguments are displayed.') from None
    if result.returncode:
        message=result.stderr or result.stdout
        if secret:message=message.replace(secret,'[redacted]')
        raise RuntimeError(message.strip())
    return result.stdout

@contextlib.contextmanager
def searchable(keychain):
    # codesign requires even an explicitly named keychain on the user search list.
    # Add ours only while signing, preserve all existing/concurrently added entries.
    keychain=str(keychain)
    before=shlex.split(run(['/usr/bin/security','list-keychains','-d','user']))
    added=keychain not in before
    if added:run(['/usr/bin/security','list-keychains','-d','user','-s',*before,keychain])
    try:yield
    finally:
        if added:
            current=shlex.split(run(['/usr/bin/security','list-keychains','-d','user']))
            if keychain in current:run(['/usr/bin/security','list-keychains','-d','user','-s',*[p for p in current if p!=keychain]])

def setup():
    if CONFIG.exists():
        print('A local signing identity already exists. Reusing it; not generating a replacement.')
        return
    STATE.mkdir(parents=True,exist_ok=True);os.chmod(STATE,0o700)
    os.umask(0o077)
    keychain=STATE/'JustVibeRemote.keychain-db'
    if keychain.exists():raise RuntimeError('An incomplete signing keychain exists. Inspect it before retrying; identity was not replaced.')
    password=secrets.token_hex(32)
    with tempfile.TemporaryDirectory(prefix='justviberemote-signing-') as temporary:
        root=pathlib.Path(temporary);os.chmod(root,0o700)
        config=root/'certificate.cnf';config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=JustVibeRemote Local Development\n[ext]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,digitalSignature,keyCertSign\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
        passfile=root/'pass';passfile.write_text(password);os.chmod(passfile,0o600)
        created=False;trusted=False
        cert=STATE/'certificate.pem'
        try:
            run(['/usr/bin/openssl','req','-new','-newkey','rsa:3072','-x509','-days','3650','-nodes','-config',config,'-keyout',root/'key.pem','-out',cert])
            run(['/usr/bin/openssl','pkcs12','-export','-inkey',root/'key.pem','-in',cert,'-out',root/'identity.p12','-passout','file:'+str(passfile)])
            run(['/usr/bin/security','create-keychain','-p',password,keychain],password);created=True
            run(['/usr/bin/security','unlock-keychain','-p',password,keychain],password)
            run(['/usr/bin/security','import',root/'identity.p12','-k',keychain,'-P',password,'-T','/usr/bin/codesign','-x'],password)
            # User domain only, constrained to code-signing policy. No TLS/system trust.
            run(['/usr/bin/security','add-trusted-cert','-r','trustRoot','-p','codeSign','-k',keychain,cert],timeout=240);trusted=True
            # Scope key access to Apple signing tools in this dedicated keychain only.
            run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:','-s','-k',password,keychain],password)
            fingerprint=run(['/usr/bin/openssl','x509','-in',cert,'-noout','-fingerprint','-sha1']).strip().split('=',1)[1].replace(':','')
            shutil.copy('/usr/bin/true',root/'signing-check')
            with searchable(keychain):
                run(['/usr/bin/codesign','--force','--sign',fingerprint,'--keychain',keychain,'--timestamp=none',root/'signing-check'])
                run(['/usr/bin/codesign','--verify','--strict',root/'signing-check'])
            CONFIG.write_text(json.dumps({'keychain':str(keychain),'fingerprint':fingerprint,'password':password},indent=2));os.chmod(CONFIG,0o600)
            print('Created persistent local signing identity. User code-signing trust only; no system or website trust changes.')
        except BaseException:
            if cert.exists():
                try:subprocess.run(['/usr/bin/security','remove-trusted-cert',str(cert)],capture_output=True,timeout=5)
                except subprocess.TimeoutExpired:pass
            if created:subprocess.run(['/usr/bin/security','delete-keychain',str(keychain)],capture_output=True)
            cert.unlink(missing_ok=True)
            raise
        finally:
            if created:subprocess.run(['/usr/bin/security','lock-keychain',str(keychain)],capture_output=True)

def sign(app):
    if not CONFIG.exists():raise RuntimeError('Stable signing is not set up. Run: python3 scripts/local-signing.py setup. Or supply JUSTVIBEREMOTE_SIGNING_IDENTITY with your own certificate. No ad-hoc fallback was used.')
    info=json.loads(CONFIG.read_text());password=info['password'];keychain=info['keychain']
    try:
        run(['/usr/bin/security','unlock-keychain','-p',password,keychain],password)
        with searchable(keychain):
            run(['/usr/bin/codesign','--force','--sign',info['fingerprint'],'--keychain',keychain,'--timestamp=none',app],password)
            run(['/usr/bin/codesign','--verify','--strict',app],password)
        print('Signed with the persistent local development identity.')
    finally:subprocess.run(['/usr/bin/security','lock-keychain',keychain],capture_output=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['setup','sign']);parser.add_argument('app',nargs='?');args=parser.parse_args()
    try:
        if args.action=='setup':setup()
        elif args.app:sign(args.app)
        else:parser.error('sign requires an app path')
    except Exception as error:raise SystemExit(str(error))
