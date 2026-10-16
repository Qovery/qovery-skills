use super::*;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::sync::{mpsc, Arc};

fn setup() -> (tempfile::TempDir, Tracker, PathBuf) {
    let tmp = tempfile::tempdir().unwrap();
    let tracker = Tracker {
        root: tmp.path().join("qovery-skills"),
    };
    let path = tracker.start("qovery-signup", "abc1234").unwrap().unwrap();
    (tmp, tracker, path)
}
fn org() -> &'static str {
    "11111111-1111-4111-8111-111111111111"
}
fn org2() -> &'static str {
    "22222222-2222-4222-8222-222222222222"
}
fn creds() -> Option<(String, String)> {
    Some(("Bearer synthetic-session".into(), "account-a".into()))
}
fn read(tracker: &Tracker, path: &Path) -> Run {
    tracker.state(path, false).unwrap().1
}
#[derive(Default)]
struct Mock {
    calls: Vec<(bool, Metadata, String, Option<String>)>,
    code: u16,
}
impl Transport for Mock {
    fn request(
        &mut self,
        associated: bool,
        run: &Run,
        authorization: Option<&str>,
    ) -> Result<Response> {
        self.calls.push((
            associated,
            run.metadata.clone(),
            run.secret.clone(),
            authorization.map(str::to_owned),
        ));
        Ok(Response {
            code: if self.code == 0 { 202 } else { self.code },
            body: json!({"event_id":Uuid::new_v4(),"run_id":run.metadata.run_id,"delivery_status":"PENDING"}),
            retry_after: 120,
        })
    }
}
#[test]
fn anonymous_abandonment_absent_auth_connected_and_new_accounts() {
    let (_tmp, t, p) = setup();
    let mut mock = Mock::default();
    t.flush(&p, &mut mock, None, || None).unwrap();
    t.flush(&p, &mut mock, Some(org()), || None).unwrap();
    assert_eq!(mock.calls.len(), 1);
    assert!(mock.calls[0].3.is_none());
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    assert_eq!(mock.calls.len(), 2);
    assert_eq!(mock.calls[0].1, mock.calls[1].1);
    assert_eq!(mock.calls[0].2, mock.calls[1].2);
    assert_eq!((mock.calls[0].0, mock.calls[1].0), (false, true));
    let text = fs::read_to_string(&p).unwrap();
    assert!(!text.contains("Bearer"));
    let other = t.start("qovery-signup", "abc1234").unwrap().unwrap();
    assert_ne!(
        read(&t, &p).metadata.run_id,
        read(&t, &other).metadata.run_id
    );
    assert_ne!(
        read(&t, &p).metadata.anonymous_id,
        read(&t, &other).metadata.anonymous_id
    );
}
#[test]
fn retry_preserves_ids_secret_timestamp_and_account_org_guard() {
    let (_tmp, t, p) = setup();
    let mut mock = Mock {
        code: 503,
        ..Default::default()
    };
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    let mut run = read(&t, &p);
    assert!(run.start.next_at >= run.created + 119.0);
    assert!(run.associate.as_ref().unwrap().next_at >= run.created + 119.0);
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    assert_eq!(mock.calls.len(), 2);
    run.start.next_at = 0.0;
    run.associate.as_mut().unwrap().next_at = 0.0;
    save(&p, &run).unwrap();
    t.flush(&p, &mut mock, Some(org2()), creds).unwrap();
    assert_eq!(mock.calls.len(), 3); // only the pending start may retry under an account/org switch
    t.flush(&p, &mut mock, Some(org()), || {
        Some(("Bearer other".into(), "account-b".into()))
    })
    .unwrap();
    assert_eq!(mock.calls.len(), 3);
    let mut run = read(&t, &p);
    run.start.next_at = 0.0;
    save(&p, &run).unwrap();
    mock.code = 202;
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    assert_eq!(mock.calls.len(), 5);
    for (_, metadata, secret, _) in &mock.calls {
        assert_eq!(metadata, &run.metadata);
        assert_eq!(secret, &run.secret);
    }
    let accepted = read(&t, &p);
    assert!(accepted.start.event_id.is_some());
    assert!(accepted.associate.unwrap().event_id.is_some());
}
#[test]
fn resume_never_retries_an_association_implicitly() {
    let (_tmp, t, p) = setup();
    let mut mock = Mock {
        code: 503,
        ..Default::default()
    };
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    let mut run = read(&t, &p);
    run.start.status = "accepted".into();
    run.associate.as_mut().unwrap().next_at = 0.0;
    save(&p, &run).unwrap();
    t.flush(&p, &mut mock, None, || {
        panic!("anonymous resume must not fetch auth")
    })
    .unwrap();
    assert_eq!(mock.calls.len(), 2);
    mock.code = 202;
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    assert_eq!(mock.calls.len(), 3);
}
#[test]
fn rejections_backoff_and_invalid_acceptance() {
    for code in [204, 400, 401, 403, 404, 408, 409, 410, 413, 429, 503] {
        let (_tmp, t, p) = setup();
        let mut mock = Mock {
            code,
            ..Default::default()
        };
        t.flush(&p, &mut mock, None, || None).unwrap();
        let event = read(&t, &p).start;
        assert_eq!(event.last_http_status, Some(code));
        assert_eq!(
            event.status,
            if [401, 408, 429, 503].contains(&code) {
                "pending"
            } else {
                "stopped"
            }
        );
    }
    struct Invalid;
    impl Transport for Invalid {
        fn request(&mut self, _: bool, _: &Run, _: Option<&str>) -> Result<Response> {
            Ok(Response {
                code: 202,
                body: json!({"event_id":"bad"}),
                retry_after: 0,
            })
        }
    }
    let (_tmp, t, p) = setup();
    t.flush(&p, &mut Invalid, None, || None).unwrap();
    assert_eq!(read(&t, &p).start.status, "pending");
}
#[test]
fn private_state_symlinks_expiration_and_orphans() {
    let (_tmp, t, p) = setup();
    assert_eq!(fs::metadata(&p).unwrap().mode() & 0o777, 0o600);
    assert_eq!(
        fs::metadata(p.parent().unwrap()).unwrap().mode() & 0o777,
        0o700
    );
    fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap();
    assert!(t.state(&p, false).is_err());
    fs::set_permissions(&p, fs::Permissions::from_mode(0o600)).unwrap();
    let original = p.with_file_name("original");
    fs::rename(&p, &original).unwrap();
    symlink(&original, &p).unwrap();
    assert!(t.state(&p, false).is_err());
    fs::remove_file(&p).unwrap();
    fs::rename(original, &p).unwrap();
    let mut run = read(&t, &p);
    run.created = now() - TTL - 1.0;
    save(&p, &run).unwrap();
    let mut mock = Mock::default();
    t.flush(&p, &mut mock, None, || None).unwrap();
    assert!(!p.parent().unwrap().exists());
    assert!(mock.calls.is_empty());
    for i in 0..MAX_RUNS {
        DirBuilder::new()
            .mode(0o700)
            .create(t.root.join(format!("run-orphan-{i}")))
            .unwrap();
    }
    let created = t.start("qovery-deploy", "abc1234").unwrap().unwrap();
    assert_eq!(t.paths().unwrap(), vec![created]);
    // Unknown or linked content is never deleted by orphan cleanup.
    let outside = t.root.join("outside");
    fs::write(&outside, "untouched").unwrap();
    let dir = t.root.join("run-unsafe");
    DirBuilder::new().mode(0o700).create(&dir).unwrap();
    symlink(&outside, dir.join(".state-link")).unwrap();
    let _queue = Lock::acquire(&t.root.join("queue.lock"), true).unwrap();
    t.prune().unwrap();
    assert_eq!(fs::read_to_string(outside).unwrap(), "untouched");
    assert!(dir.exists());
}
#[test]
fn queue_is_bounded_and_root_router_excluded() {
    let (_tmp, t, _p) = setup();
    assert!(t.start("qovery", "abc1234").unwrap().is_none());
    assert!(!valid_skill("qovery-../bad"));
    assert!(!valid_skill("qovery-\n"));
    assert!(!valid_version("bad\nheader"));
    for _ in 1..MAX_RUNS {
        t.start("qovery-deploy", "abc1234").unwrap();
    }
    assert!(t.start("qovery-deploy", "abc1234").unwrap().is_none());
}
#[test]
fn association_and_cleanup_wait_for_workers() {
    for cleanup in [false, true] {
        let (_tmp, t, p) = setup();
        let t = Arc::new(t);
        let p = Arc::new(p);
        let (lock, _) = t.state(&p, false).unwrap();
        assert!(t.state(&p, false).is_err());
        let (entered, rx) = mpsc::channel();
        let (done, result) = mpsc::channel();
        let tt = t.clone();
        let pp = p.clone();
        let thread = thread::spawn(move || {
            entered.send(()).unwrap();
            let r = if cleanup {
                tt.cleanup(&pp)
            } else {
                tt.flush(&pp, &mut Mock::default(), Some(org()), creds)
            };
            done.send(r.is_ok()).unwrap();
        });
        rx.recv_timeout(Duration::from_secs(1)).unwrap();
        assert!(result.recv_timeout(Duration::from_millis(100)).is_err());
        drop(lock);
        assert!(result.recv_timeout(Duration::from_secs(2)).unwrap());
        thread.join().unwrap();
        if cleanup {
            assert!(!p.exists());
        } else {
            assert_eq!(read(&t, &p).associate.unwrap().status, "accepted");
        }
    }
}
fn bearer(alg: &str, claims: Value) -> String {
    format!(
        "Bearer {}.{}.synthetic",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&json!({"alg":alg})).unwrap()),
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims).unwrap())
    )
}
#[test]
fn only_human_bearer_candidates_and_python_guard_compatibility() {
    let header = bearer("RS256", json!({"iss":"test-issuer","sub":"user-a"}));
    let (_, fingerprint) = credentials_from_header(&header).unwrap();
    assert_eq!(
        fingerprint,
        hex(&Sha256::digest(b"[\"test-issuer\", \"user-a\"]"))
    );
    for header in [
        "Token synthetic".to_owned(),
        "Bearer invalid".to_owned(),
        header + "\nextra",
        bearer("HS256", json!({"iss":"a","sub":"b"})),
        bearer(
            "RS256",
            json!({"iss":"a","sub":"b","gty":"client-credentials"}),
        ),
    ] {
        assert!(credentials_from_header(&header).is_none());
    }
}
#[test]
fn python_state_is_resumed_without_changing_identity_or_proof() {
    let (_tmp, t, p) = setup();
    let legacy = json!({"created":now(),"secret":"0123456789abcdef".repeat(4),"association":null,"metadata":{"run_id":"c7cb0586-457b-41b8-bf1c-0f6b39764a8d","anonymous_id":"11111111-1111-4111-8111-111111111111","skill_name":"qovery-signup","skill_version":"abc1234","started_at":"2026-10-14T10:00:00.000Z"},"start":{"status":"pending","attempts":2,"next_at":0}});
    fs::write(&p, serde_json::to_vec(&legacy).unwrap()).unwrap();
    let mut mock = Mock::default();
    t.flush(&p, &mut mock, Some(org()), creds).unwrap();
    let run = read(&t, &p);
    assert_eq!(
        serde_json::to_value(run.metadata).unwrap(),
        legacy["metadata"]
    );
    assert_eq!(run.secret, legacy["secret"]);
}
#[test]
fn curl_config_has_exact_contract_and_no_auth_for_start() {
    let (_tmp, t, p) = setup();
    let mut run = read(&t, &p);
    let config = request_config(false, &run, None).unwrap();
    assert!(config.contains("/v1/skillRuns/start"));
    assert!(!config.contains("Authorization"));
    assert!(config.contains("User-Agent: QoverySkill/qovery-signup (version:abc1234; https://github.com/Qovery/qovery-skills)"));
    run.association = Some(Association {
        organization: org().into(),
        account_fingerprint: "a".into(),
    });
    let config = request_config(true, &run, Some("Bearer synthetic")).unwrap();
    assert!(config.contains(&format!("/v1/organization/{}/skillRuns/associate", org())));
    assert!(config.contains("Authorization: Bearer synthetic"));
    assert_eq!(
        serde_json::to_value(&run.metadata)
            .unwrap()
            .as_object()
            .unwrap()
            .len(),
        5
    );
}
#[test]
fn subprocess_deadline_includes_blocked_stdin_and_caps_output() {
    let start = Instant::now();
    let bytes = vec![b'x'; 1024 * 1024];
    assert!(bounded(Command::new("sleep").arg("3"), Some(&bytes), 1, 10).is_err());
    assert!(start.elapsed() < Duration::from_secs(2));
    assert!(bounded(Command::new("printf").arg("oversized"), None, 1, 3).is_err());
}
#[test]
fn simulation_records_no_secret_or_auth() {
    let (tmp, t, p) = setup();
    let log = tmp.path().join("events");
    let run = read(&t, &p);
    t.flush(&p, &mut Simulated(log.clone()), Some(org()), creds)
        .unwrap();
    let text = fs::read_to_string(&log).unwrap();
    assert_eq!(text.lines().count(), 2);
    assert!(!text.contains(&run.secret));
    assert!(!text.contains("Bearer"));
    assert!(!text.contains("account-a"));
}
