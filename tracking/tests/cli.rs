//! End-to-end tests with installed copies and an isolated PATH: no Python or real HTTP.
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde_json::{json, Value};
use std::{
    fs,
    os::unix::fs::{symlink, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output},
    thread,
    time::{Duration, Instant},
};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}
fn binary() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_skill-run"))
}
fn script(p: &Path, text: &str) {
    fs::write(p, text).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}
struct Installed {
    tmp: tempfile::TempDir,
    dir: PathBuf,
    bin: PathBuf,
}
impl Installed {
    fn new() -> Self {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("skill");
        let bin = tmp.path().join("bin");
        fs::create_dir_all(dir.join("scripts")).unwrap();
        fs::create_dir(&bin).unwrap();
        fs::copy(binary(), dir.join("scripts/skill-run")).unwrap();
        fs::copy(
            root().join("_shared/scripts/track-skill-usage.sh"),
            dir.join("scripts/track-skill-usage.sh"),
        )
        .unwrap();
        fs::write(dir.join("_version.txt"), "abc1234\n").unwrap();
        symlink("/bin/bash", bin.join("bash")).unwrap();
        symlink("/usr/bin/dirname", bin.join("dirname")).unwrap();
        Self { tmp, dir, bin }
    }
    fn command(&self) -> Command {
        let mut c = Command::new("/bin/bash");
        c.arg(self.dir.join("scripts/track-skill-usage.sh"))
            .env("PATH", &self.bin)
            .env("XDG_STATE_HOME", self.tmp.path().join("state"))
            .env("HOME", self.tmp.path())
            .env("QOVERY_SKILLS_NO_TRACKING", "");
        c
    }
    fn run(&self, args: &[&str]) -> Output {
        self.command().args(args).output().unwrap()
    }
    fn wait(&self, path: &Path, kind: &str) -> Value {
        let until = Instant::now() + Duration::from_secs(4);
        loop {
            if let Ok(text) = fs::read_to_string(path) {
                if let Ok(v) = serde_json::from_str::<Value>(&text) {
                    if v[kind]["status"] == "accepted" {
                        return v;
                    }
                }
            }
            assert!(Instant::now() < until, "worker did not finish");
            thread::sleep(Duration::from_millis(10));
        }
    }
}
#[test]
fn installed_wrappers_simulate_connected_journey_without_python() {
    let i = Installed::new();
    let log = i.tmp.path().join("events");
    // No Python executable exists in the worker's PATH.
    let out = i.run(&[
        "start",
        "qovery-signup",
        "--simulate",
        log.to_str().unwrap(),
    ]);
    assert!(out.status.success());
    let path = PathBuf::from(String::from_utf8(out.stdout).unwrap().trim());
    let first = i.wait(&path, "start");
    let header = format!(
        "Bearer {}.{}.synthetic",
        URL_SAFE_NO_PAD.encode(br#"{"alg":"RS256"}"#),
        URL_SAFE_NO_PAD.encode(br#"{"iss":"test-issuer","sub":"user-a"}"#)
    );
    script(
        &i.bin.join("qovery"),
        &format!("#!/bin/sh\nprintf '%s\\n' '{header}'\n"),
    );
    let out = i.run(&[
        "associate",
        path.to_str().unwrap(),
        "--organization",
        "11111111-1111-4111-8111-111111111111",
        "--simulate",
        log.to_str().unwrap(),
    ]);
    assert!(out.status.success());
    let associated = i.wait(&path, "associate");
    assert_eq!(first["metadata"], associated["metadata"]);
    assert!(!fs::read_to_string(&path).unwrap().contains(&header));
    let text = fs::read_to_string(log).unwrap();
    assert_eq!(text.lines().count(), 2);
    assert!(!text.contains(first["secret"].as_str().unwrap()));
    assert!(i.run(&["cleanup", path.to_str().unwrap()]).status.success());
    assert!(!path.parent().unwrap().exists());
    for wrapper in fs::read_dir(root())
        .unwrap()
        .flatten()
        .map(|e| e.path().join("scripts/track-skill-usage.sh"))
        .filter(|p| p.is_file())
    {
        assert_eq!(
            fs::read(wrapper).unwrap(),
            fs::read(root().join("_shared/scripts/track-skill-usage.sh")).unwrap()
        );
    }
}
#[test]
fn optout_dev_missing_binary_and_invalid_xdg_are_safe() {
    let i = Installed::new();
    let log = i.tmp.path().join("events");
    let args = [
        "start",
        "qovery-signup",
        "--simulate",
        log.to_str().unwrap(),
    ];
    let out = i
        .command()
        .args(args)
        .env("QOVERY_SKILLS_NO_TRACKING", "true")
        .output()
        .unwrap();
    assert!(out.stdout.is_empty());
    assert!(!i.tmp.path().join("state").exists());
    fs::remove_file(i.dir.join("_version.txt")).unwrap();
    let out = i.run(&["start", "qovery-signup"]);
    assert!(out.stdout.is_empty());
    assert!(!i.tmp.path().join("state").exists());
    for xdg in ["", "relative/state"] {
        let out = i
            .command()
            .args(args)
            .env("XDG_STATE_HOME", xdg)
            .output()
            .unwrap();
        let path = PathBuf::from(String::from_utf8(out.stdout).unwrap().trim());
        assert!(path.is_absolute());
        assert_eq!(
            path.parent().unwrap().parent().unwrap(),
            i.tmp.path().join(".local/state/qovery-skills")
        );
        i.wait(&path, "start");
        i.run(&["cleanup", path.to_str().unwrap()]);
    }
    fs::remove_file(i.dir.join("scripts/skill-run")).unwrap();
    let out = i
        .command()
        .args(args)
        .env("QOVERY_SKILLS_TRACKING_DEBUG", "1")
        .output()
        .unwrap();
    assert!(out.status.success());
    assert!(String::from_utf8(out.stderr)
        .unwrap()
        .contains("native helper unavailable"));
}
#[test]
fn real_curl_transport_uses_mocked_executable_and_safe_debug() {
    let i = Installed::new();
    let log = i.tmp.path().join("events");
    let out = i.run(&[
        "start",
        "qovery-deploy",
        "--simulate",
        log.to_str().unwrap(),
    ]);
    let path = PathBuf::from(String::from_utf8(out.stdout).unwrap().trim());
    let mut run = i.wait(&path, "start");
    run["start"] = json!({"status":"pending","attempts":0,"next_at":0});
    fs::write(&path, serde_json::to_vec(&run).unwrap()).unwrap();
    let skipped = Command::new(i.dir.join("scripts/skill-run"))
        .args(["worker", path.to_str().unwrap()])
        .env("PATH", &i.bin)
        .env("XDG_STATE_HOME", i.tmp.path().join("state"))
        .env("QOVERY_SKILLS_NO_TRACKING", "1")
        .env("QOVERY_SKILLS_TRACKING_DEBUG", "1")
        .output()
        .unwrap();
    assert!(String::from_utf8(skipped.stderr)
        .unwrap()
        .contains("ignored (opt-out)"));
    assert_eq!(
        serde_json::from_str::<Value>(&fs::read_to_string(&path).unwrap()).unwrap(),
        run
    );
    script(
        &i.bin.join("curl"),
        r#"#!/bin/sh
[ "$1" = --disable ] || exit 91
case "$*" in *Bearer*|*X-Qovery-Skill-Run-Secret*) exit 92 ;; esac
while [ "$#" -gt 0 ]; do
 case "$1" in --output) body=$2; shift ;; --dump-header) headers=$2; shift ;; esac
 shift
done
config=$(/bin/cat)
case "$config" in *'User-Agent: QoverySkill/qovery-deploy (version:abc1234;'*) ;; *) exit 93 ;; esac
printf '{"run_id":"%s","event_id":"11111111-1111-4111-8111-111111111111","delivery_status":"PENDING"}' "$TEST_RUN_ID" > "$body"
printf 'HTTP/1.1 202 Accepted\r\n' > "$headers"
printf 202
"#,
    );
    let out = Command::new(i.dir.join("scripts/skill-run"))
        .args(["worker", path.to_str().unwrap()])
        .env("PATH", &i.bin)
        .env("XDG_STATE_HOME", i.tmp.path().join("state"))
        .env("TEST_RUN_ID", run["metadata"]["run_id"].as_str().unwrap())
        .env("QOVERY_SKILLS_NO_TRACKING", "")
        .env("QOVERY_SKILLS_TRACKING_DEBUG", "1")
        .output()
        .unwrap();
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
    let debug = String::from_utf8(out.stderr).unwrap();
    assert!(debug.contains("HTTP 202"), "{debug}");
    assert!(!debug.contains(run["secret"].as_str().unwrap()));
    assert!(!debug.contains("Bearer"));
    i.wait(&path, "start");
}
