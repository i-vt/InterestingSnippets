import time
import os

class dhcTimer:
    def __init__(self):
        self._start_time = None

    def start(self):
        print("[dhc.plsTimeIt]\tTimer started")
        self._start_time = time.time()

    def end(self):
        if self._start_time is None:
            raise RuntimeError("[dhc.plsTimeIt]\tTimer was not started.")
        elapsed = time.time() - self._start_time
        print(f"[dhc.plsTimeIt]\tTime to execute: {elapsed:.6f} seconds")
        self._start_time = None  # Reset timer after use


def dhc_track_var(name, value):
    print(f"[dhc.plsTrackVar]\tVariable {name}: {value}")


def dhc_run(command):
    while True:
        response = input(f"[dhc.plsRun]\tRun \"{command}\"?\nY / N: ").strip().lower()
        if response in {"n", "no"}:
            break
        elif response in {"y", "yes", ""}:
            os.system(command)
            break
        else:
            print("[dhc.plsRun]\tPlease enter Y or N.")


def dhc_pause():
    input("[dhc.plsPause]\tPress [ENTER] to continue")


def dhc_error():
    raise Exception("[dhc.plsError]\tError created")
