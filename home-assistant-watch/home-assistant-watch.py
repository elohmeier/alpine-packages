#!/usr/bin/env python3
"""Bounded recovery of HA process, API and recorder failures on OpenRC."""
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class Watch:
    def __init__(self, env=None):
        self.env = os.environ if env is None else env
        self.root = Path(self.env.get("HASS_WATCH_STATE_DIR", "/run/home-assistant-watch"))
        self.root.mkdir(parents=True, exist_ok=True, mode=0o755)
        self.statefile = self.root / "state.json"
        self.metrics = Path(self.env.get("HASS_WATCH_METRICS", "/run/home-assistant-watch/metrics"))
        self.wanted = Path(self.env.get("HASS_WATCH_WANTED", "/run/home-assistant-container.wanted"))
        self.pause = Path(self.env.get("HASS_WATCH_PAUSE", "/run/home-assistant-maintenance"))
        self.base = self.env.get("HASS_WATCH_URL", "http://localhost:8123").rstrip("/")
        self.entity = self.env.get("HASS_WATCH_ENTITY", "")
        self.token = self.env.get("HASS_WATCH_TOKEN", "")
        self.grace = int(self.env.get("HASS_WATCH_GRACE", "300"))
        self.threshold = int(self.env.get("HASS_WATCH_THRESHOLD", "3"))
        self.backoff = int(self.env.get("HASS_WATCH_RESTART_BACKOFF", "300"))
        self.window = int(self.env.get("HASS_WATCH_RESTART_WINDOW", "3600"))
        self.max_restarts = int(self.env.get("HASS_WATCH_MAX_RESTARTS", "3"))
        self.history_window = int(self.env.get("HASS_WATCH_HISTORY_WINDOW", "600"))
        self.service = self.env.get("HASS_WATCH_SERVICE", "home-assistant-container")
        try:
            self.state = json.loads(self.statefile.read_text())
        except (OSError, ValueError):
            self.state = {}
        if self.state.get("clock") != "monotonic":
            # /run belongs to this boot. NTP can jump wall time by months on a
            # diskless Pi; recovery timers must use uptime instead. Preserve
            # recent attempt ages when upgrading the previous state format.
            now, wall = time.monotonic(), time.time()
            old_attempts = self.state.get("attempts", [])
            attempts = [now - max(0, wall - t) for t in old_attempts if wall - t < self.window]
            last_attempt = self.state.get("last_attempt", 0)
            self.state = {"clock": "monotonic", "failures": 0,
                          "last_attempt": last_attempt,
                          "last_attempt_mono": max(attempts, default=-self.backoff),
                          "attempts": attempts, "started": "",
                          "grace_until": now + self.grace}

    def log(self, message):
        print(dt.datetime.now(dt.timezone.utc).isoformat() + " " + message, flush=True)

    def run(self, command, timeout=15):
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)

    def container(self):
        # The image lives in an additional read-only store. Using the default
        # Podman storage config for inspect can report false corruption.
        result = self.run(["/bin/sh", "-c", '. /usr/lib/podman-container/functions.sh; '
            '. /etc/conf.d/home-assistant-container; '
            'export CONTAINERS_STORAGE_CONF="$(get_storage_conf "$CONTAINER_IMAGE")"; '
            'podman container exists home-assistant; result=$?; '
            '[ "$result" = 1 ] && exit 10; [ "$result" = 0 ] || exit 11; '
            "podman inspect --format '{{json .State}}' home-assistant"])
        if result.returncode == 10:
            return {"Running": False, "Status": "missing"}
        if result.returncode:
            raise RuntimeError("container inspection failed")
        return json.loads(result.stdout)

    def api(self, path):
        req = urllib.request.Request(self.base + path,
                headers={"Authorization": "Bearer " + self.token})
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)

    def probe(self):
        if not self.token or not self.entity:
            return "configuration", False
        stage = "config"
        try:
            config = self.api("/api/config")
            if config.get("state") != "RUNNING":
                return "startup_stuck", True
            if "components" in config and not {"recorder", "history"}.issubset(config["components"]):
                return "recorder_missing", True
            stage = "entity"
            entity = self.api("/api/states/" + urllib.parse.quote(self.entity, safe=""))
            updated = dt.datetime.fromisoformat(entity["last_updated"].replace("Z", "+00:00")).timestamp()
            if entity.get("state") in ("unknown", "unavailable") or time.time() - updated > self.history_window:
                return "recorder_probe_stale", False
            start = dt.datetime.fromtimestamp(time.time() - self.history_window, dt.timezone.utc).isoformat()
            stage = "history"
            history = self.api("/api/history/period/" + urllib.parse.quote(start, safe="") + "?" +
                urllib.parse.urlencode({"filter_entity_id": self.entity, "minimal_response": ""}))
            # A boundary state alone is not proof of a current recorder write.
            recent = any(dt.datetime.fromisoformat(row["last_changed"].replace("Z", "+00:00")).timestamp()
                         >= time.time() - self.history_window
                         for group in history for row in group if "last_changed" in row)
            return ("healthy", False) if recent else ("recorder_stalled", True)
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                return "authentication", False
            if exc.code == 404:
                if stage == "history":
                    return "recorder_missing", True
                return "configuration", False
            return "api_http_failure", True
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            return "api_unreachable", True
        except (ValueError, KeyError, TypeError):
            return "invalid_api_response", False

    def capture(self, reason):
        directory = Path(self.env.get("HASS_WATCH_EVIDENCE_DIR", "/var/log/home-assistant-recovery"))
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(directory, 0o700)
        target = directory / (str(time.time_ns()) + ".json")
        evidence = {"reason": reason, "time": dt.datetime.now(dt.timezone.utc).isoformat()}
        try:
            evidence["container_state"] = self.container()
        except Exception as exc:
            evidence["container_state_error"] = type(exc).__name__
        for name, cmd in {
            "kernel": ["dmesg"],
            "container_log": ["/bin/sh", "-c", '. /usr/lib/podman-container/functions.sh; '
                '. /etc/conf.d/home-assistant-container; '
                'podman_run "$CONTAINER_IMAGE" logs --tail 200 home-assistant'],
        }.items():
            try:
                result = self.run(cmd)
                evidence[name] = (result.stdout + result.stderr)[-262144:]
            except Exception as exc:
                evidence[name] = type(exc).__name__
        evidence["meminfo"] = Path("/proc/meminfo").read_text()
        target.write_text(json.dumps(evidence))
        os.chmod(target, 0o600)
        for old in sorted(directory.glob("*.json"))[:-3]:
            old.unlink()

    def tick(self):
        now = time.monotonic()
        running = 0
        reason, unhealthy = "maintenance", False
        self.state["attempts"] = [t for t in self.state["attempts"] if now - t < self.window]
        try:
            container = self.container()
            running = int(bool(container.get("Running")))
            if self.wanted.exists() and not self.pause.exists():
                if running and container.get("StartedAt") != self.state["started"]:
                    self.state["started"] = container.get("StartedAt", "")
                    self.state["grace_until"] = now + self.grace
                if now < self.state["grace_until"]:
                    reason = "startup_grace"
                elif not running:
                    reason, unhealthy = "container_stopped", True
                else:
                    reason, unhealthy = self.probe()
        except (subprocess.TimeoutExpired, RuntimeError, ValueError, OSError):
            if self.wanted.exists() and not self.pause.exists():
                reason = "container_inspection_failed"
        self.state["failures"] = self.state["failures"] + 1 if unhealthy else 0
        blocked = int(len(self.state["attempts"]) >= self.max_restarts)
        if unhealthy and self.state["failures"] >= self.threshold:
            if (not blocked and now - self.state["last_attempt_mono"] >= self.backoff
                    and self.wanted.exists() and not self.pause.exists()):
                # Record attempts before invoking OpenRC, including failed starts.
                self.state["last_attempt"] = time.time()
                self.state["last_attempt_mono"] = now
                self.state["attempts"].append(now)
                self.state["failures"] = 0
                self.state["grace_until"] = now + self.grace
                self.save(reason, running, blocked)
                self.log("restarting " + self.service + ": " + reason)
                try:
                    self.capture(reason)
                except Exception as exc:
                    self.log("evidence capture failed: " + type(exc).__name__)
                try:
                    result = self.run(["rc-service", self.service, "restart"], timeout=300)
                    self.log("restart result=" + str(result.returncode))
                except (subprocess.TimeoutExpired, OSError) as exc:
                    self.log("restart failed: " + type(exc).__name__)
                self.state["grace_until"] = time.monotonic() + self.grace
        blocked = int(len(self.state["attempts"]) >= self.max_restarts)
        self.save(reason, running, blocked)
        if reason != self.state.get("last_reason"):
            self.log("health=" + reason)
            self.state["last_reason"] = reason
        return reason

    def save(self, reason, running, blocked):
        self.state["reason"] = reason
        temporary = self.statefile.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.state))
        temporary.replace(self.statefile)
        values = {"container_running": running, "healthy": int(reason == "healthy"),
                  "maintenance": int(reason == "maintenance"), "startup_grace": int(reason == "startup_grace"),
                  "probe_error": int(reason in ("authentication", "configuration", "recorder_probe_stale",
                                                 "invalid_api_response", "container_inspection_failed")),
                  "restart_blocked": blocked, "restart_attempts": len(self.state["attempts"]),
                  "last_restart_unixtime": int(self.state["last_attempt"]),
                  "last_check_unixtime": int(time.time())}
        self.metrics.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.metrics.with_suffix(".tmp")
        temporary.write_text("homeassistant_watch " + ",".join(f"{key}={value}i" for key, value in values.items()) + "\n")
        os.chmod(temporary, 0o644)
        temporary.replace(self.metrics)


def main():
    watch = Watch()
    if "--capture" in sys.argv:
        watch.capture("service_start")
        return
    with (watch.root / "instance.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("watchdog already running")
        while True:
            watch.tick()
            if "--once" in sys.argv:
                return
            time.sleep(int(os.environ.get("HASS_WATCH_INTERVAL", "60")))


if __name__ == "__main__":
    main()
