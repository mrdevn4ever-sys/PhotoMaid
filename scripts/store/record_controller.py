#!/usr/bin/env python3
"""Records the real simulator in response to a narrow test-side file protocol."""
import argparse,json,os,re,signal,subprocess,time
from pathlib import Path

def atomic(path, value):
    temporary=path.with_suffix('.tmp');temporary.write_text(json.dumps(value));temporary.replace(path)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('udid');parser.add_argument('output',type=Path);args=parser.parse_args()
    control=args.output/'control';control.mkdir(parents=True,exist_ok=True)
    recordings=args.output/'recordings';recordings.mkdir(exist_ok=True)
    process=None;log=None;current=None;seen=set()
    def stop():
        nonlocal process,log,current
        if process:
            stopped=time.time()
            process.send_signal(signal.SIGINT)
            process.wait(timeout=30)
            if log:log.close()
            atomic(recordings/(current+'.recording.json'),{'name':current,'start':started,'end':stopped,'returncode':process.returncode})
        process=None;log=None;current=None
    def shutdown(*_):
        stop();raise SystemExit(0)
    signal.signal(signal.SIGTERM,shutdown)
    while True:
        for request in sorted(control.glob('request-*.json')):
            if request.name in seen:continue
            seen.add(request.name);value=json.loads(request.read_text());token=value['token'];name=value['name']
            if not re.fullmatch(r'[A-Za-z0-9-]+',token) or not re.fullmatch(r'[a-z0-9-]+',name):raise ValueError('Invalid recording request')
            try:
                if value['operation']=='start':
                    if process:raise ValueError('Already recording')
                    current=name;log=open(recordings/(name+'.log'),'wb');started=time.time()
                    process=subprocess.Popen(['xcrun','simctl','io',args.udid,'recordVideo','--codec=h264','--mask=ignored',str(recordings/(name+'.mov'))],stdout=log,stderr=log)
                    for _ in range(100):
                        if process.poll() is not None:raise RuntimeError('Recorder exited before readiness')
                        if b'Recording started' in (recordings/(name+'.log')).read_bytes():break
                        time.sleep(.1)
                    else:raise RuntimeError('Recording did not start')
                    time.sleep(.5)
                elif value['operation']=='stop':stop()
                else:raise ValueError('Unsupported recording operation')
                ack={'status':'ok'}
            except Exception as error:ack={'status':'error','error':str(error)}
            atomic(control/('ack-'+token+'.json'),ack)
        time.sleep(.1)

if __name__=='__main__':main()
