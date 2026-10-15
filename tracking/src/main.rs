//! q-core v1 lifecycle. No tokens, prompts or CLI cache in persisted state.
#![cfg(unix)]
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::{SecondsFormat, Utc};
use rand::{rngs::OsRng, Rng, RngCore};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    env,
    fs::{self, DirBuilder, File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    os::{
        fd::AsRawFd,
        unix::{
            fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt},
            process::CommandExt,
        },
    },
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tempfile::Builder;
use uuid::Uuid;

const TTL: f64 = 30.0 * 86400.0;
const MAX_RUNS: usize = 100;
const API: &str = "https://api.qovery.com";
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn debug(message: &str) {
    if env::var("QOVERY_SKILLS_TRACKING_DEBUG").as_deref() == Ok("1") {
        eprintln!("skill-tracking: {message}");
    }
}
fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
fn disabled() -> bool {
    env::var_os("QOVERY_SKILLS_NO_TRACKING").is_some_and(|s| !s.is_empty())
}
fn invalid() -> io::Error {
    io::Error::other("invalid private state")
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
struct Metadata {
    run_id: Uuid,
    anonymous_id: Uuid,
    skill_name: String,
    skill_version: String,
    started_at: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
struct Event {
    status: String,
    attempts: u32,
    next_at: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_http_status: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    event_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    delivery_status: Option<String>,
}
impl Event {
    fn pending() -> Self {
        Self {
            status: "pending".into(),
            attempts: 0,
            next_at: 0.0,
            last_http_status: None,
            event_id: None,
            delivery_status: None,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
struct Association {
    organization: String,
    account_fingerprint: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
struct Run {
    created: f64,
    secret: String,
    metadata: Metadata,
    start: Event,
    association: Option<Association>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    associate: Option<Event>,
}

fn private_dir(path: &Path) -> Result<()> {
    let m = fs::symlink_metadata(path)?;
    // SAFETY: geteuid has no preconditions.
    if !m.is_dir() || m.uid() != unsafe { libc::geteuid() } || m.mode() & 0o7777 != 0o700 {
        return Err(invalid().into());
    }
    Ok(())
}
fn private_open(path: &Path, create: bool) -> Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(create)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?;
    let m = file.metadata()?;
    // SAFETY: geteuid has no preconditions.
    if !m.is_file() || m.uid() != unsafe { libc::geteuid() } || m.mode() & 0o7777 != 0o600 {
        return Err(invalid().into());
    }
    Ok(file)
}
struct Lock(File);
impl Lock {
    fn acquire(path: &Path, blocking: bool) -> Result<Self> {
        let file = private_open(path, true)?;
        // SAFETY: valid owned fd; flock does not retain the pointer or fd.
        if unsafe {
            libc::flock(
                file.as_raw_fd(),
                libc::LOCK_EX | if blocking { 0 } else { libc::LOCK_NB },
            )
        } != 0
        {
            return Err(io::Error::last_os_error().into());
        }
        Ok(Self(file))
    }
}
impl Drop for Lock {
    fn drop(&mut self) {
        // SAFETY: our owned fd is still live.
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}
struct Tracker {
    root: PathBuf,
}
impl Tracker {
    fn from_env() -> Result<Self> {
        let base = match env::var_os("XDG_STATE_HOME").map(PathBuf::from) {
            Some(p) if p.is_absolute() => p,
            _ => PathBuf::from(env::var_os("HOME").ok_or_else(invalid)?).join(".local/state"),
        };
        if !base.is_absolute() {
            return Err(invalid().into());
        }
        Ok(Self {
            root: base.join("qovery-skills"),
        })
    }
    fn prepare(&self) -> Result<()> {
        DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&self.root)?;
        private_dir(&self.root)
    }
    fn paths(&self) -> Result<Vec<PathBuf>> {
        let mut paths = fs::read_dir(&self.root)?
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with("run-"))
            .map(|e| e.path().join("state.json"))
            .collect::<Vec<_>>();
        paths.sort();
        Ok(paths)
    }
    fn state(&self, path: &Path, blocking: bool) -> Result<(Lock, Run)> {
        let directory = path.parent().ok_or_else(invalid)?;
        if !path.is_absolute()
            || path
                .components()
                .any(|c| !matches!(c, Component::RootDir | Component::Normal(_)))
            || path.file_name().is_none_or(|n| n != "state.json")
            || directory.parent() != Some(self.root.as_path())
            || directory
                .file_name()
                .is_none_or(|n| !n.to_string_lossy().starts_with("run-"))
        {
            return Err(invalid().into());
        }
        private_dir(&self.root)?;
        private_dir(directory)?;
        let lock = Lock::acquire(&directory.join("lock"), blocking)?;
        let file = private_open(path, false)?;
        if file.metadata()?.len() > 65536 {
            return Err(invalid().into());
        }
        let run: Run = serde_json::from_reader(file)?;
        if !run.created.is_finite()
            || run.secret.len() != 64
            || !run
                .secret
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        {
            return Err(invalid().into());
        }
        Ok((lock, run))
    }
    fn prune(&self) -> Result<()> {
        for path in self.paths()? {
            let Some(dir) = path.parent() else { continue };
            if private_dir(dir).is_err() {
                continue;
            }
            // Only start/prune (both under queue.lock) can create state-less runs.
            if fs::symlink_metadata(&path).is_err_and(|e| e.kind() == io::ErrorKind::NotFound) {
                if let Ok(entries) = fs::read_dir(dir) {
                    for entry in entries.flatten() {
                        let name = entry.file_name();
                        if (name == "lock" || name.to_string_lossy().starts_with(".state-"))
                            && private_open(&entry.path(), false).is_ok()
                        {
                            let _ = fs::remove_file(entry.path());
                        }
                    }
                }
                let _ = fs::remove_dir(dir);
            } else if let Ok((_lock, run)) = self.state(&path, false) {
                if now() - run.created >= TTL {
                    let _ = remove_run(&path);
                }
            }
        }
        Ok(())
    }
    fn start(&self, skill: &str, version: &str) -> Result<Option<PathBuf>> {
        if disabled() {
            debug("ignored (opt-out)");
            return Ok(None);
        }
        if !valid_skill(skill) {
            debug("ignored (unsupported skill)");
            return Ok(None);
        }
        if !valid_version(version) {
            return Err(invalid().into());
        }
        self.prepare()?;
        let _queue = Lock::acquire(&self.root.join("queue.lock"), true)?;
        self.prune()?;
        if self.paths()?.len() >= MAX_RUNS {
            debug("ignored (queue full)");
            return Ok(None);
        }
        let directory = Builder::new()
            .prefix("run-")
            .permissions(fs::Permissions::from_mode(0o700))
            .tempdir_in(&self.root)?
            .keep();
        let path = directory.join("state.json");
        let mut bytes = [0u8; 32];
        OsRng.fill_bytes(&mut bytes);
        let run = Run {
            created: now(),
            secret: hex(&bytes),
            association: None,
            associate: None,
            metadata: Metadata {
                run_id: Uuid::new_v4(),
                anonymous_id: Uuid::new_v4(),
                skill_name: skill.into(),
                skill_version: version.into(),
                started_at: Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
            },
            start: Event::pending(),
        };
        save(&path, &run)?;
        Ok(Some(path))
    }
    fn flush(
        &self,
        path: &Path,
        transport: &mut impl Transport,
        organization: Option<&str>,
        credentials: impl FnOnce() -> Option<(String, String)>,
    ) -> Result<()> {
        if disabled() {
            debug("ignored (opt-out)");
            return Ok(());
        }
        let (_lock, mut run) = self.state(path, organization.is_some())?;
        if now() - run.created >= TTL {
            remove_run(path)?;
            debug("ignored (expired)");
            return Ok(());
        }
        send(false, &mut run, transport, None);
        save(path, &run)?;
        let Some(org) = organization else {
            return Ok(());
        };
        let org = Uuid::parse_str(org)?.to_string();
        let Some((header, fingerprint)) = credentials() else {
            debug("ignored (human auth absent)");
            return Ok(());
        };
        let target = Association {
            organization: org,
            account_fingerprint: fingerprint,
        };
        if run.association.as_ref().is_some_and(|old| old != &target) {
            debug("ignored (account or organization changed; new execution required)");
            return Ok(());
        }
        if run.association.is_none() {
            run.association = Some(target);
            run.associate = Some(Event::pending());
            save(path, &run)?;
        }
        send(true, &mut run, transport, Some(&header));
        save(path, &run)
    }
    fn cleanup(&self, path: &Path) -> Result<()> {
        let (_lock, _) = self.state(path, true)?;
        remove_run(path)
    }
}
fn valid_skill(s: &str) -> bool {
    s.len() <= 80
        && s.strip_prefix("qovery-").is_some_and(|rest| {
            !rest.is_empty()
                && rest.as_bytes()[0].is_ascii_lowercase_or_digit()
                && rest
                    .bytes()
                    .all(|b| b.is_ascii_lowercase_or_digit() || b"._-".contains(&b))
        })
}
trait LowerDigit {
    fn is_ascii_lowercase_or_digit(&self) -> bool;
}
impl LowerDigit for u8 {
    fn is_ascii_lowercase_or_digit(&self) -> bool {
        self.is_ascii_lowercase() || self.is_ascii_digit()
    }
}
fn valid_version(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 80
        && s.as_bytes()[0].is_ascii_alphanumeric()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
}
fn save(path: &Path, run: &Run) -> Result<()> {
    let mut temp = Builder::new()
        .prefix(".state-")
        .tempfile_in(path.parent().ok_or_else(invalid)?)?;
    serde_json::to_writer(&mut temp, run)?;
    temp.as_file().sync_all()?;
    temp.persist(path).map_err(|_| invalid())?;
    Ok(())
}
fn remove_run(path: &Path) -> Result<()> {
    fs::remove_file(path)?;
    let dir = path.parent().ok_or_else(invalid)?;
    fs::remove_file(dir.join("lock"))?;
    fs::remove_dir(dir)?;
    Ok(())
}

struct Response {
    code: u16,
    body: Value,
    retry_after: u64,
}
trait Transport {
    fn request(
        &mut self,
        associate: bool,
        run: &Run,
        authorization: Option<&str>,
    ) -> Result<Response>;
}
fn send(
    associate: bool,
    run: &mut Run,
    transport: &mut impl Transport,
    authorization: Option<&str>,
) {
    let kind = if associate { "associate" } else { "start" };
    let item = if associate {
        run.associate.as_ref().unwrap()
    } else {
        &run.start
    };
    if item.status != "pending" || now() < item.next_at || disabled() {
        debug("ignored (accepted, stopped, delayed or opt-out)");
        return;
    }
    debug(&format!("attempted ({kind})"));
    let response = transport
        .request(associate, run, authorization)
        .unwrap_or(Response {
            code: 0,
            body: Value::Null,
            retry_after: 0,
        });
    let mut code = response.code;
    debug(&format!(
        "response ({kind}: {})",
        if code == 0 {
            "network or invalid response".into()
        } else {
            format!("HTTP {code}")
        }
    ));
    let item = if associate {
        run.associate.as_mut().unwrap()
    } else {
        &mut run.start
    };
    item.last_http_status = Some(code);
    if code == 202 {
        let id = response.body["event_id"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok());
        let status = response.body["delivery_status"].as_str();
        if id.is_some()
            && response.body["run_id"].as_str() == Some(run.metadata.run_id.to_string().as_str())
            && status.is_some_and(|s| ["PENDING", "DELIVERED", "FAILED"].contains(&s))
        {
            item.status = "accepted".into();
            item.event_id = id;
            item.delivery_status = status.map(str::to_owned);
            debug(&format!("accepted ({kind})"));
            return;
        }
        code = 0;
    }
    if code == 204 || ((300..500).contains(&code) && ![401, 408, 429].contains(&code)) {
        item.status = "stopped".into();
        debug("ignored (opt-out or permanent rejection)");
        return;
    }
    item.attempts = item.attempts.saturating_add(1);
    let mut delay = (5.0
        * 2f64.powi(item.attempts.saturating_sub(1).min(10) as i32)
        * OsRng.gen_range(0.8..=1.2))
    .min(3600.0);
    if [429, 503].contains(&code) {
        delay = delay.max(60.0).max(response.retry_after as f64);
    }
    item.next_at = now() + delay;
    debug("failed (queued for retry)");
}

// Private pipes keep the Bearer token/config in memory, with size and time bounds.
fn bounded(
    command: &mut Command,
    input: Option<&[u8]>,
    timeout: u64,
    max_output: u64,
) -> Result<Vec<u8>> {
    command
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    let mut child = command.spawn()?;
    let deadline = Instant::now() + Duration::from_secs(timeout);
    let result = (|| -> Result<Vec<u8>> {
        fn nonblocking(fd: i32) -> io::Result<()> {
            // SAFETY: caller owns the live pipe fd; no pointer or ownership transfer.
            let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
            if flags == -1
                || unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } == -1
            {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        }
        let mut stdout = child.stdout.take().ok_or_else(invalid)?;
        nonblocking(stdout.as_raw_fd())?;
        let mut stdin = child.stdin.take();
        if let Some(pipe) = &stdin {
            nonblocking(pipe.as_raw_fd())?;
        }
        let mut input = input.unwrap_or_default();
        let mut output = Vec::new();
        let mut eof = false;
        loop {
            let mut buf = [0u8; 1024];
            match stdout.read(&mut buf) {
                Ok(0) => eof = true,
                Ok(n) => {
                    if output.len() + n > max_output as usize {
                        return Err(invalid().into());
                    }
                    output.extend_from_slice(&buf[..n]);
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {}
                Err(e) => return Err(e.into()),
            }
            if let Some(pipe) = &mut stdin {
                if !input.is_empty() {
                    match pipe.write(input) {
                        Ok(0) => return Err(invalid().into()),
                        Ok(n) => input = &input[n..],
                        Err(e) if e.kind() == io::ErrorKind::WouldBlock => {}
                        Err(e) => return Err(e.into()),
                    }
                }
                if input.is_empty() {
                    stdin.take();
                }
            }
            if let Some(status) = child.try_wait()? {
                if !status.success() {
                    return Err(invalid().into());
                }
                if eof {
                    return Ok(output);
                }
            }
            if Instant::now() >= deadline {
                return Err(io::Error::new(io::ErrorKind::TimedOut, "command deadline").into());
            }
            thread::sleep(Duration::from_millis(10));
        }
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    result
}
fn credentials_from_header(header: &str) -> Option<(String, String)> {
    if header.len() > 16384 || header.contains(['\r', '\n']) {
        return None;
    }
    let parts = header
        .strip_prefix("Bearer ")?
        .split('.')
        .collect::<Vec<_>>();
    if parts.len() != 3 {
        return None;
    }
    let decode = |part: &str| -> Option<Value> {
        serde_json::from_slice(&URL_SAFE_NO_PAD.decode(part.trim_end_matches('=')).ok()?).ok()
    };
    let alg = decode(parts[0])?;
    let claims = decode(parts[1])?;
    let iss = claims["iss"].as_str()?;
    let sub = claims["sub"].as_str()?;
    if alg["alg"] != "RS256"
        || iss.is_empty()
        || sub.is_empty()
        || claims["gty"] == "client-credentials"
    {
        return None;
    }
    // Match Python json.dumps([iss, sub]) for existing account-switch guards.
    fn python_string(s: &str) -> String {
        serde_json::to_string(s)
            .unwrap()
            .chars()
            .map(|c| {
                if c < '\u{007f}' {
                    c.to_string()
                } else {
                    c.encode_utf16(&mut [0; 2])
                        .iter()
                        .map(|u| format!("\\u{u:04x}"))
                        .collect()
                }
            })
            .collect()
    }
    let fingerprint = hex(&Sha256::digest(
        format!("[{}, {}]", python_string(iss), python_string(sub)).as_bytes(),
    ));
    Some((header.to_owned(), fingerprint))
}
fn session() -> Option<(String, String)> {
    let bytes = bounded(
        Command::new("qovery").args(["auth", "token", "--print", "--authorization-header"]),
        None,
        3,
        16384,
    )
    .ok()?;
    credentials_from_header(std::str::from_utf8(&bytes).ok()?.trim())
}
fn quoted(s: &str) -> String {
    format!(
        "\"{}\"",
        s.replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
    )
}
fn request_config(associate: bool, run: &Run, authorization: Option<&str>) -> Result<String> {
    let endpoint = if associate {
        format!(
            "/v1/organization/{}/skillRuns/associate",
            run.association.as_ref().ok_or_else(invalid)?.organization
        )
    } else {
        "/v1/skillRuns/start".into()
    };
    let mut lines = vec![
        format!("url = {}", quoted(&format!("{API}{endpoint}"))),
        "request = \"POST\"".into(),
        format!("data = {}", quoted(&serde_json::to_string(&run.metadata)?)),
    ];
    let mut headers = vec![
        "Content-Type: application/json".into(),
        format!("X-Qovery-Skill-Run-Secret: {}", run.secret),
        format!(
            "User-Agent: QoverySkill/{} (version:{}; https://github.com/Qovery/qovery-skills)",
            run.metadata.skill_name, run.metadata.skill_version
        ),
    ];
    if let Some(header) = authorization {
        headers.push(format!("Authorization: {header}"));
    }
    lines.extend(headers.iter().map(|h| format!("header = {}", quoted(h))));
    Ok(lines.join("\n"))
}
struct Curl;
impl Transport for Curl {
    fn request(
        &mut self,
        associate: bool,
        run: &Run,
        authorization: Option<&str>,
    ) -> Result<Response> {
        let dir = Builder::new()
            .prefix("qovery-tracking-http-")
            .permissions(fs::Permissions::from_mode(0o700))
            .tempdir()?;
        let body = dir.path().join("body");
        let headers = dir.path().join("headers");
        let config = request_config(associate, run, authorization)?;
        let bytes = bounded(
            Command::new("curl")
                .args([
                    "--disable",
                    "--config",
                    "-",
                    "--silent",
                    "--connect-timeout",
                    "3",
                    "--max-time",
                    "8",
                    "--max-filesize",
                    "4096",
                    "--output",
                ])
                .arg(&body)
                .arg("--dump-header")
                .arg(&headers)
                .args(["--write-out", "%{http_code}"]),
            Some(config.as_bytes()),
            9,
            3,
        )?;
        let code = std::str::from_utf8(&bytes)?.parse::<u16>()?;
        let payload = if code == 202 {
            let f = File::open(&body)?;
            serde_json::from_reader(f.take(4096))?
        } else {
            Value::Null
        };
        let mut text = String::new();
        File::open(&headers)?.take(8192).read_to_string(&mut text)?;
        let retry_after = text
            .lines()
            .filter_map(|l| l.split_once(':'))
            .filter(|(k, _)| k.eq_ignore_ascii_case("retry-after"))
            .map(|(_, v)| v.trim().parse::<u64>().unwrap_or(60))
            .next_back()
            .unwrap_or(0);
        Ok(Response {
            code,
            body: payload,
            retry_after,
        })
    }
}
struct Simulated(PathBuf);
impl Transport for Simulated {
    fn request(&mut self, associate: bool, run: &Run, _: Option<&str>) -> Result<Response> {
        let mut file = private_open(&self.0, true)?;
        // SAFETY: valid owned fd. The file closes immediately after the record.
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 {
            return Err(io::Error::last_os_error().into());
        }
        file.seek(SeekFrom::End(0))?;
        writeln!(
            file,
            "{}",
            json!({"kind":if associate {"associate"}else{"start"},"metadata":run.metadata,"organization":if associate {run.association.as_ref().map(|a|a.organization.as_str())}else{None}})
        )?;
        Ok(Response {
            code: 202,
            body: json!({"run_id":run.metadata.run_id,"event_id":Uuid::new_v4(),"delivery_status":"PENDING"}),
            retry_after: 0,
        })
    }
}
fn installed_version() -> Option<String> {
    let exe = env::current_exe().ok()?;
    let v = fs::read_to_string(exe.parent()?.parent()?.join("_version.txt")).ok()?;
    Some(v.trim().into())
}
fn spawn(path: &Path, organization: Option<&str>, simulate: Option<&str>) -> Result<()> {
    let mut cmd = Command::new(env::current_exe()?);
    cmd.arg("worker").arg(path);
    if let Some(org) = organization {
        cmd.args(["--organization", org]);
    }
    if let Some(log) = simulate {
        cmd.args(["--simulate", log]);
    }
    cmd.stdin(Stdio::null()).stdout(Stdio::null()).stderr(
        if env::var("QOVERY_SKILLS_TRACKING_DEBUG").as_deref() == Ok("1") {
            Stdio::inherit()
        } else {
            Stdio::null()
        },
    );
    // SAFETY: setsid is async-signal-safe; no allocation or inherited locks used.
    unsafe {
        cmd.pre_exec(|| {
            if libc::setsid() == -1 {
                Err(io::Error::last_os_error())
            } else {
                Ok(())
            }
        });
    }
    cmd.spawn()?;
    Ok(())
}
fn main_result() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.as_slice() == ["--version"] {
        println!("skill-run {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    if args.len() < 2 {
        debug("ignored (use lifecycle command)");
        return Ok(());
    }
    let action = &args[0];
    let value = &args[1];
    let mut org = None;
    let mut simulate = None;
    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--organization" => {
                i += 1;
                org = Some(args.get(i).ok_or_else(invalid)?.as_str());
            }
            "--simulate" => {
                i += 1;
                simulate = Some(args.get(i).ok_or_else(invalid)?.as_str());
            }
            _ => return Err(invalid().into()),
        };
        i += 1;
    }
    let tracker = Tracker::from_env()?;
    if action == "cleanup" {
        return tracker.cleanup(Path::new(value));
    }
    if disabled() {
        debug("ignored (opt-out)");
        return Ok(());
    }
    let version = installed_version();
    if version.is_none() && simulate.is_none() {
        debug("ignored (development install)");
        return Ok(());
    }
    match action.as_str() {
        "start" => {
            if let Some(path) = tracker.start(value, version.as_deref().unwrap_or("simulation"))? {
                println!("{}", path.display());
                io::stdout().flush()?;
                spawn(&path, None, simulate)?;
            }
        }
        "resume" | "associate" => {
            if action == "associate" && org.is_none() {
                debug("ignored (explicit organization required)");
                return Ok(());
            }
            spawn(
                Path::new(value),
                if action == "associate" { org } else { None },
                simulate,
            )?;
        }
        "worker" => {
            fn work(
                tracker: &Tracker,
                path: &Path,
                org: Option<&str>,
                transport: &mut impl Transport,
            ) -> Result<()> {
                tracker.flush(path, transport, org, session)?;
                let mut drained = 0;
                for other in tracker.paths()? {
                    if other == path {
                        continue;
                    }
                    let due = tracker.state(&other, false).is_ok_and(|(_, r)| {
                        r.start.status == "pending" && r.start.next_at <= now()
                    });
                    if due && tracker.flush(&other, transport, None, || None).is_ok() {
                        drained += 1;
                        if drained == 2 {
                            break;
                        }
                    }
                }
                Ok(())
            }
            if let Some(log) = simulate {
                work(
                    &tracker,
                    Path::new(value),
                    org,
                    &mut Simulated(PathBuf::from(log)),
                )?;
            } else {
                work(&tracker, Path::new(value), org, &mut Curl)?;
            }
        }
        _ => debug("ignored (use lifecycle command)"),
    };
    Ok(())
}
fn main() {
    if main_result().is_err() {
        debug("failed (local state or runtime unavailable)");
    }
}

#[cfg(test)]
mod tests;
