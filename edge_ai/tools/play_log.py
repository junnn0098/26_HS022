#!/usr/bin/env python3
"""저장된 데모 로그를 실시간처럼 한 줄씩 재생 (영상 녹화용).

사용법:
    python3 play_log.py demo_fall.log            # 0.5초 간격 재생
    python3 play_log.py demo_fall.log --delay 0.5
    python3 play_log.py demo_fall.log --no-color
"""
import argparse, sys, time

R="\033[0m"; DIM="\033[90m"; GREEN="\033[92m"; YEL="\033[93m"; RED="\033[91m"; BOLD="\033[1m"

def colorize(line, color=True):
    if not color:
        return line
    if "[!]" in line or "fall-suspect" in line:
        c = RED
    elif ". movement" in line or "movement" in line:
        c = YEL
    elif "normal" in line:
        c = GREEN
    else:
        return BOLD + line + R   # 헤더
    # 타임스탬프/pps는 흐리게, 나머지는 상태색
    return c + line + R

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logfile")
    ap.add_argument("--delay", type=float, default=0.5)
    ap.add_argument("--no-color", action="store_true")
    args = ap.parse_args()
    with open(args.logfile, encoding="utf-8") as f:
        lines = [l.rstrip("\n") for l in f]
    for i, line in enumerate(lines):
        print(colorize(line, not args.no_color), flush=True)
        # 헤더/저장줄은 빠르게, 데이터 줄만 delay
        if line.startswith("[") :
            time.sleep(args.delay)
        else:
            time.sleep(0.1)

if __name__ == "__main__":
    main()
