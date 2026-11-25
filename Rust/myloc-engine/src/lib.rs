//! MyLoc Rust Engine
//!
//! Independent FFI wrapper around the MIT-licensed `idevice` crate for
//! connecting to iOS developer location simulation services over a local tunnel.
//!
//! Design guarantees (NFR-111):
//! - No panics cross the FFI boundary (`catch_unwind` on every exported symbol).
//! - Thread-safe internal state protected by `Mutex`.
//! - No sensitive data (coordinates, pairing keys, PINs) is logged.

use std::ffi::{CStr, c_char};
use std::net::{IpAddr, SocketAddr};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Mutex;
use std::time::Duration;

use idevice::core_device_proxy::CoreDeviceProxy;
use idevice::dvt::location_simulation::LocationSimulationClient;
use idevice::dvt::remote_server::RemoteServerClient;
use idevice::pairing_file::PairingFile;
use idevice::provider::TcpProvider;
use idevice::remote_pairing::tunnel::connect_tls_psk_tunnel_native;
use idevice::remote_pairing::{RemotePairingClient, RpPairingFile, RpPairingSocket};
use idevice::rsd::RsdHandshake;
use idevice::{IdeviceService, RsdService};
use tokio::net::TcpStream;
use tokio::runtime::Runtime;

/// FFI status / failure stage codes aligned with Requirements §7.2.
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MyLocStatus {
    Ok = 0,
    PairingRecord = 1,
    TunnelUnreachable = 2,
    ServiceNotFound = 3,
    PairVerifyRejected = 4,
    TunnelCreate = 5,
    TunnelSecure = 6,
    RsdHandshake = 7,
    LocationService = 8,
    InitialWrite = 9,
    ActiveWrite = 10,
    Restore = 11,
    InvalidArgument = 90,
    NotConnected = 91,
    InternalError = 99,
}

struct ActiveSession {
    /// Kept alive for the duration of the location simulation session.
    /// We hold a boxed future-agnostic command channel to a dedicated tokio task
    /// that owns the `RemoteServerClient` + `LocationSimulationClient` so lifetimes
    /// remain completely safe without self-referential structs.
    cmd_tx: tokio::sync::mpsc::Sender<SessionCommand>,
    task_handle: tokio::task::JoinHandle<()>,
}

enum SessionCommand {
    SetLocation {
        lat: f64,
        lon: f64,
        reply: tokio::sync::oneshot::Sender<MyLocStatus>,
    },
    ClearLocation {
        reply: tokio::sync::oneshot::Sender<MyLocStatus>,
    },
    Shutdown {
        reply: tokio::sync::oneshot::Sender<()>,
    },
}

struct ActivePairing {
    pin_tx: Option<tokio::sync::oneshot::Sender<String>>,
    result_rx: tokio::sync::oneshot::Receiver<Result<Vec<u8>, MyLocStatus>>,
    task_handle: tokio::task::JoinHandle<()>,
}

pub struct MyLocEngineHandle {
    rt: Runtime,
    session: Mutex<Option<ActiveSession>>,
    pairing: Mutex<Option<ActivePairing>>,
    last_status: Mutex<MyLocStatus>,
    last_error_msg: Mutex<String>,
}

impl MyLocEngineHandle {
    fn set_last(&self, status: MyLocStatus) -> i32 {
        if let Ok(mut guard) = self.last_status.lock() {
            *guard = status;
        }
        status as i32
    }

    fn set_last_with_msg(&self, status: MyLocStatus, msg: String) -> i32 {
        if let Ok(mut guard) = self.last_error_msg.lock() {
            *guard = msg;
        }
        self.set_last(status)
    }
}

fn validate_coords(lat: f64, lon: f64) -> bool {
    lat.is_finite() && lon.is_finite() && (-90.0..=90.0).contains(&lat) && (-180.0..=180.0).contains(&lon)
}

async fn establish_session(
    host: String,
    port: u16,
    pairing_bytes: Vec<u8>,
    timeout_ms: u32,
) -> Result<(tokio::sync::mpsc::Sender<SessionCommand>, tokio::task::JoinHandle<()>), (MyLocStatus, String)> {
    let ip: IpAddr = host.parse().map_err(|e| (MyLocStatus::InvalidArgument, format!("ip: {e}")))?;
    let addr = SocketAddr::new(ip, port);
    let total_timeout = Duration::from_millis(timeout_ms.max(1000) as u64);

    // 1. TCP reachability check
    let _probe = tokio::time::timeout(Duration::from_secs(3), TcpStream::connect(addr))
        .await
        .map_err(|_| (MyLocStatus::TunnelUnreachable, format!("probe timeout {addr}")))?
        .map_err(|e| (MyLocStatus::TunnelUnreachable, format!("probe {addr}: {e}")))?;
    drop(_probe);

    // 2. Choose path based on pairing file format:
    //    - RpPairingFile (.mobiledevicepairing / remote pairing) -> Network RPPairing + TLS-PSK CDTunnel (10.7.0.1:49152)
    //    - Legacy lockdownd PairingFile (.plist) -> CoreDeviceProxy over TcpProvider
    let (mut adapter, rsd_port) = if let Ok(mut rp_file) = RpPairingFile::from_bytes(&pairing_bytes) {
        let stream = tokio::time::timeout(Duration::from_secs(4), TcpStream::connect(addr))
            .await
            .map_err(|_| (MyLocStatus::TunnelUnreachable, format!("connect {addr} timeout")))?
            .map_err(|e| (MyLocStatus::TunnelUnreachable, format!("connect {addr}: {e}")))?;

        let socket = RpPairingSocket::new(stream);
        let mut client = RemotePairingClient::new(socket, "MyLoc");
        tokio::time::timeout(
            total_timeout,
            client.connect(&mut rp_file, || async { "000000".to_string() }),
        )
        .await
        .map_err(|_| (MyLocStatus::PairVerifyRejected, "RPPairing connect timeout".to_string()))?
        .map_err(|e| (MyLocStatus::PairVerifyRejected, format!("RPPairing: {e:?}")))?;

        let tunnel_port = tokio::time::timeout(Duration::from_secs(4), client.create_tcp_listener())
            .await
            .map_err(|_| (MyLocStatus::TunnelCreate, "create_tcp_listener timeout".to_string()))?
            .map_err(|e| (MyLocStatus::TunnelCreate, format!("create_tcp_listener: {e:?}")))?;

        let tunnel_addr = SocketAddr::new(ip, tunnel_port);
        let tunnel_stream = tokio::time::timeout(Duration::from_secs(4), TcpStream::connect(tunnel_addr))
            .await
            .map_err(|_| (MyLocStatus::TunnelCreate, format!("tunnel connect {tunnel_addr} timeout")))?
            .map_err(|e| (MyLocStatus::TunnelCreate, format!("tunnel connect {tunnel_addr}: {e}")))?;

        let cd_tunnel = tokio::time::timeout(
            Duration::from_secs(4),
            connect_tls_psk_tunnel_native(tunnel_stream, client.encryption_key()),
        )
        .await
        .map_err(|_| (MyLocStatus::TunnelSecure, "TLS-PSK CDTunnel timeout".to_string()))?
        .map_err(|e| (MyLocStatus::TunnelSecure, format!("TLS-PSK CDTunnel: {e:?}")))?;

        let rsd_port = cd_tunnel.info.server_rsd_port;
        let our_ip = cd_tunnel
            .info
            .client_address
            .parse::<IpAddr>()
            .map_err(|e| (MyLocStatus::TunnelSecure, format!("client_address: {e}")))?;
        let their_ip = cd_tunnel
            .info
            .server_address
            .parse::<IpAddr>()
            .map_err(|e| (MyLocStatus::TunnelSecure, format!("server_address: {e}")))?;
        let mtu = cd_tunnel.info.mtu as usize;
        let mut raw_adapter = idevice::tcp::adapter::Adapter::new(Box::new(cd_tunnel.into_inner()), our_ip, their_ip);
        raw_adapter.set_mss(mtu.saturating_sub(60));
        let adapter = raw_adapter.to_async_handle();
        (adapter, rsd_port)
    } else {
        let pairing_file = PairingFile::from_bytes(&pairing_bytes)
            .map_err(|e| (MyLocStatus::PairingRecord, format!("PairingFile::from_bytes: {e:?}")))?;

        let provider = TcpProvider {
            addr: ip,
            pairing_file,
            label: "myloc-engine".to_string(),
            scope_id: None,
        };

        let proxy = tokio::time::timeout(total_timeout, CoreDeviceProxy::connect(&provider))
            .await
            .map_err(|_| (MyLocStatus::TunnelCreate, "CoreDeviceProxy::connect timeout".to_string()))?
            .map_err(|e| {
                let msg = format!("CoreDeviceProxy: {e:?}");
                let low = msg.to_lowercase();
                if low.contains("pair") || low.contains("trust") || low.contains("cert") {
                    (MyLocStatus::PairVerifyRejected, msg)
                } else {
                    (MyLocStatus::TunnelCreate, msg)
                }
            })?;

        let rsd_port = proxy.tunnel_info().server_rsd_port;
        let adapter = proxy
            .create_software_tunnel()
            .map_err(|e| (MyLocStatus::TunnelSecure, format!("create_software_tunnel: {e:?}")))?
            .to_async_handle();
        (adapter, rsd_port)
    };

    // 5. RSD handshake
    let rsd_stream = tokio::time::timeout(
        Duration::from_secs(4),
        adapter.connect(rsd_port),
    )
    .await
    .map_err(|_| (MyLocStatus::RsdHandshake, format!("adapter.connect({rsd_port}) timeout")))?
    .map_err(|e| (MyLocStatus::RsdHandshake, format!("adapter.connect({rsd_port}): {e:?}")))?;

    let mut handshake = tokio::time::timeout(
        Duration::from_secs(4),
        RsdHandshake::new(rsd_stream),
    )
    .await
    .map_err(|_| (MyLocStatus::RsdHandshake, "RsdHandshake::new timeout".to_string()))?
    .map_err(|e| (MyLocStatus::RsdHandshake, format!("RsdHandshake::new: {e:?}")))?;

    // 6. Connect RemoteServerClient (DVT) over RSD
    let mut remote_server = tokio::time::timeout(
        Duration::from_secs(4),
        RemoteServerClient::connect_rsd(&mut adapter, &mut handshake),
    )
    .await
    .map_err(|_| (MyLocStatus::ServiceNotFound, "RemoteServerClient::connect_rsd timeout".to_string()))?
    .map_err(|e| (MyLocStatus::ServiceNotFound, format!("RemoteServerClient::connect_rsd: {e:?}")))?;

    // 7. Spawn dedicated session actor owning remote_server + LocationSimulationClient
    let (cmd_tx, mut cmd_rx) = tokio::sync::mpsc::channel::<SessionCommand>(16);
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel::<Result<(), (MyLocStatus, String)>>();

    let task_handle = tokio::spawn(async move {
        let _keep_adapter = adapter;
        let mut loc_client = match LocationSimulationClient::new(&mut remote_server).await {
            Ok(c) => {
                let _ = ready_tx.send(Ok(()));
                c
            }
            Err(e) => {
                let _ = ready_tx.send(Err((MyLocStatus::LocationService, format!("LocationSimulationClient::new: {e:?}"))));
                return;
            }
        };

        while let Some(cmd) = cmd_rx.recv().await {
            match cmd {
                SessionCommand::SetLocation { lat, lon, reply } => {
                    let res = match loc_client.set(lat, lon).await {
                        Ok(()) => MyLocStatus::Ok,
                        Err(_) => MyLocStatus::ActiveWrite,
                    };
                    let _ = reply.send(res);
                }
                SessionCommand::ClearLocation { reply } => {
                    let res = match loc_client.clear().await {
                        Ok(()) => MyLocStatus::Ok,
                        Err(_) => MyLocStatus::Restore,
                    };
                    let _ = reply.send(res);
                }
                SessionCommand::Shutdown { reply } => {
                    let _ = reply.send(());
                    break;
                }
            }
        }
    });

    match ready_rx.await {
        Ok(Ok(())) => Ok((cmd_tx, task_handle)),
        Ok(Err(e)) => {
            task_handle.abort();
            Err(e)
        }
        Err(_) => {
            task_handle.abort();
            Err((MyLocStatus::LocationService, "ready_rx dropped".to_string()))
        }
    }
}

/// Creates a new engine handle. Caller must release with `myloc_engine_destroy`.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_create() -> *mut MyLocEngineHandle {
    let result = catch_unwind(|| {
        let rt = Runtime::new().ok()?;
        Some(Box::into_raw(Box::new(MyLocEngineHandle {
            rt,
            session: Mutex::new(None),
            pairing: Mutex::new(None),
            last_status: Mutex::new(MyLocStatus::Ok),
            last_error_msg: Mutex::new(String::new()),
        })))
    });
    match result {
        Ok(Some(ptr)) => ptr,
        _ => std::ptr::null_mut(),
    }
}

/// Destroys an engine handle and shuts down any active session.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_destroy(handle: *mut MyLocEngineHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        let boxed = unsafe { Box::from_raw(handle) };
        if let Ok(mut guard) = boxed.session.lock() {
            if let Some(active) = guard.take() {
                let (tx, rx) = tokio::sync::oneshot::channel();
                let _ = active.cmd_tx.blocking_send(SessionCommand::Shutdown { reply: tx });
                let _ = boxed.rt.block_on(async {
                    let _ = tokio::time::timeout(Duration::from_secs(2), rx).await;
                });
                active.task_handle.abort();
            }
        }
    }));
}

/// Probes TCP reachability of the local tunnel endpoint (e.g. `10.7.0.1:49152`).
/// Returns `0` (`MyLocStatus::Ok`) if reachable, `2` (`TunnelUnreachable`) otherwise.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_probe_tunnel(
    host: *const c_char,
    port: u16,
    timeout_ms: u32,
) -> i32 {
    let res = catch_unwind(|| {
        if host.is_null() {
            return MyLocStatus::InvalidArgument as i32;
        }
        let host_str = match unsafe { CStr::from_ptr(host) }.to_str() {
            Ok(s) => s,
            Err(_) => return MyLocStatus::InvalidArgument as i32,
        };
        let ip: IpAddr = match host_str.parse() {
            Ok(ip) => ip,
            Err(_) => return MyLocStatus::InvalidArgument as i32,
        };
        let addr = SocketAddr::new(ip, port);
        let timeout = Duration::from_millis(timeout_ms.max(200) as u64);
        match std::net::TcpStream::connect_timeout(&addr, timeout) {
            Ok(_) => MyLocStatus::Ok as i32,
            Err(_) => MyLocStatus::TunnelUnreachable as i32,
        }
    });
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Connects to the device's DVT LocationSimulation service over the local tunnel.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_connect(
    handle: *mut MyLocEngineHandle,
    host: *const c_char,
    port: u16,
    pairing_bytes: *const u8,
    pairing_len: usize,
    timeout_ms: u32,
) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || host.is_null() || pairing_bytes.is_null() || pairing_len == 0 {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        let host_str = match unsafe { CStr::from_ptr(host) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return engine.set_last(MyLocStatus::InvalidArgument),
        };
        let bytes = unsafe { std::slice::from_raw_parts(pairing_bytes, pairing_len) }.to_vec();

        // Tear down any existing session first
        if let Ok(mut guard) = engine.session.lock() {
            if let Some(old) = guard.take() {
                old.task_handle.abort();
            }
        }

        match engine.rt.block_on(establish_session(host_str, port, bytes, timeout_ms)) {
            Ok((cmd_tx, task_handle)) => {
                if let Ok(mut guard) = engine.session.lock() {
                    *guard = Some(ActiveSession { cmd_tx, task_handle });
                }
                engine.set_last_with_msg(MyLocStatus::Ok, String::new())
            }
            Err((status, msg)) => engine.set_last_with_msg(status, msg),
        }
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Writes a simulated coordinate to the active session without reconnecting.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_set_location(
    handle: *mut MyLocEngineHandle,
    latitude: f64,
    longitude: f64,
) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || !validate_coords(latitude, longitude) {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        let tx = match engine.session.lock() {
            Ok(guard) => match guard.as_ref() {
                Some(active) => active.cmd_tx.clone(),
                None => return engine.set_last(MyLocStatus::NotConnected),
            },
            Err(_) => return engine.set_last(MyLocStatus::InternalError),
        };

        let status = engine.rt.block_on(async {
            let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
            if tx
                .send(SessionCommand::SetLocation {
                    lat: latitude,
                    lon: longitude,
                    reply: reply_tx,
                })
                .await
                .is_err()
            {
                return MyLocStatus::ActiveWrite;
            }
            match tokio::time::timeout(Duration::from_secs(4), reply_rx).await {
                Ok(Ok(s)) => s,
                _ => MyLocStatus::ActiveWrite,
            }
        });
        engine.set_last(status)
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Clears simulated location so the system can resume real GPS.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_clear_location(handle: *mut MyLocEngineHandle) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        let tx = match engine.session.lock() {
            Ok(guard) => match guard.as_ref() {
                Some(active) => active.cmd_tx.clone(),
                None => return engine.set_last(MyLocStatus::NotConnected),
            },
            Err(_) => return engine.set_last(MyLocStatus::InternalError),
        };

        let status = engine.rt.block_on(async {
            let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
            if tx
                .send(SessionCommand::ClearLocation { reply: reply_tx })
                .await
                .is_err()
            {
                return MyLocStatus::Restore;
            }
            match tokio::time::timeout(Duration::from_secs(4), reply_rx).await {
                Ok(Ok(s)) => s,
                _ => MyLocStatus::Restore,
            }
        });
        engine.set_last(status)
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Disconnects and cleans up the active session.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_disconnect(handle: *mut MyLocEngineHandle) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        if let Ok(mut guard) = engine.session.lock() {
            if let Some(active) = guard.take() {
                let (tx, rx) = tokio::sync::oneshot::channel();
                let _ = engine.rt.block_on(async {
                    let _ = active.cmd_tx.send(SessionCommand::Shutdown { reply: tx }).await;
                    let _ = tokio::time::timeout(Duration::from_secs(2), rx).await;
                });
                active.task_handle.abort();
            }
        }
        engine.set_last(MyLocStatus::Ok)
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Returns the last status code recorded by this engine handle.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_last_error_code(handle: *mut MyLocEngineHandle) -> i32 {
    if handle.is_null() {
        return MyLocStatus::InvalidArgument as i32;
    }
    let engine = unsafe { &*handle };
    engine
        .last_status
        .lock()
        .map(|g| *g as i32)
        .unwrap_or(MyLocStatus::InternalError as i32)
}

/// Copies the last non-sensitive error message into `out_buf` (NUL-terminated).
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_last_error_message(
    handle: *mut MyLocEngineHandle,
    out_buf: *mut u8,
    out_cap: usize,
) -> usize {
    if handle.is_null() || out_buf.is_null() || out_cap == 0 {
        return 0;
    }
    let engine = unsafe { &*handle };
    let msg = engine
        .last_error_msg
        .lock()
        .map(|g| g.clone())
        .unwrap_or_default();
    let bytes = msg.as_bytes();
    let n = bytes.len().min(out_cap - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf, n);
        *out_buf.add(n) = 0;
    }
    n
}

/// Performs full RPPairing over the local tunnel (`host:port`).
/// On iOS, this triggers the system "Trust / 信任" consent dialog (`awaitingUserConsent`)
/// and returns the resulting `.mobiledevicepairing` bytes once accepted.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_pair_device(
    handle: *mut MyLocEngineHandle,
    host: *const c_char,
    port: u16,
    timeout_ms: u32,
    out_buf: *mut u8,
    out_cap: usize,
    out_len: *mut usize,
) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || host.is_null() || out_buf.is_null() || out_len.is_null() || out_cap == 0 {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        let host_str = match unsafe { CStr::from_ptr(host) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return engine.set_last_with_msg(MyLocStatus::InvalidArgument, "invalid host".into()),
        };
        let ip: IpAddr = match host_str.parse() {
            Ok(ip) => ip,
            Err(_) => return engine.set_last_with_msg(MyLocStatus::InvalidArgument, "invalid IP".into()),
        };
        let addr = SocketAddr::new(ip, port);
        let timeout = Duration::from_millis(timeout_ms.max(5000) as u64);

        let outcome = engine.rt.block_on(async {
            let stream = tokio::time::timeout(Duration::from_secs(5), TcpStream::connect(addr))
                .await
                .map_err(|_| (MyLocStatus::TunnelUnreachable, "TCP connect timeout".to_string()))?
                .map_err(|e| (MyLocStatus::TunnelUnreachable, format!("TCP connect failed: {e}")))?;

            let socket = RpPairingSocket::new(stream);
            let mut client = RemotePairingClient::new(socket, "MyLoc");
            let mut rp_file = RpPairingFile::generate("MyLoc");

            tokio::time::timeout(timeout, client.connect(&mut rp_file, || async { "000000".to_string() }))
                .await
                .map_err(|_| (MyLocStatus::PairVerifyRejected, "等待设备信任确认超时".to_string()))?
                .map_err(|e| (MyLocStatus::PairVerifyRejected, format!("{e:?}")))?;

            Ok::<Vec<u8>, (MyLocStatus, String)>(rp_file.to_bytes())
        });

        match outcome {
            Ok(bytes) => {
                if bytes.len() > out_cap {
                    return engine.set_last_with_msg(MyLocStatus::InternalError, "buffer too small".into());
                }
                unsafe {
                    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf, bytes.len());
                    *out_len = bytes.len();
                }
                engine.set_last_with_msg(MyLocStatus::Ok, String::new())
            }
            Err((status, msg)) => engine.set_last_with_msg(status, msg),
        }
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Starts an in-app Remote Pairing session over the local tunnel (`host:port`).
/// This sends the pairing consent request so iOS displays the 6-digit PIN dialog.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_start_pairing(
    handle: *mut MyLocEngineHandle,
    host: *const c_char,
    port: u16,
    timeout_ms: u32,
) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || host.is_null() {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        let host_str = match unsafe { CStr::from_ptr(host) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return engine.set_last(MyLocStatus::InvalidArgument),
        };
        let ip: IpAddr = match host_str.parse() {
            Ok(ip) => ip,
            Err(_) => return engine.set_last(MyLocStatus::InvalidArgument),
        };
        let addr = SocketAddr::new(ip, port);
        let timeout = Duration::from_millis(timeout_ms.max(1000) as u64);

        // Cancel any previous pairing attempt
        if let Ok(mut guard) = engine.pairing.lock() {
            if let Some(old) = guard.take() {
                old.task_handle.abort();
            }
        }

        // Connect TCP synchronously within timeout before spawning pairing task
        let stream = match engine.rt.block_on(async {
            tokio::time::timeout(timeout, TcpStream::connect(addr)).await
        }) {
            Ok(Ok(s)) => s,
            _ => return engine.set_last(MyLocStatus::TunnelUnreachable),
        };

        let (pin_tx, pin_rx) = tokio::sync::oneshot::channel::<String>();
        let (prompt_tx, prompt_rx) = tokio::sync::oneshot::channel::<()>();
        let (result_tx, mut result_rx) = tokio::sync::oneshot::channel::<Result<Vec<u8>, String>>();
        let pin_rx_shared = std::sync::Arc::new(tokio::sync::Mutex::new(Some((pin_rx, prompt_tx))));

        let task_handle = engine.rt.spawn(async move {
            let socket = RpPairingSocket::new(stream);
            let mut client = RemotePairingClient::new(socket, "MyLoc");
            let mut rp_file = RpPairingFile::generate("MyLoc");

            let pair_res = client
                .connect(&mut rp_file, || {
                    let rx_holder = pin_rx_shared.clone();
                    async move {
                        let pair_opt = rx_holder.lock().await.take();
                        if let Some((rx, ptx)) = pair_opt {
                            let _ = ptx.send(());
                            rx.await.unwrap_or_default()
                        } else {
                            String::new()
                        }
                    }
                })
                .await;

            match pair_res {
                Ok(()) => {
                    let _ = result_tx.send(Ok(rp_file.to_bytes()));
                }
                Err(e) => {
                    let _ = result_tx.send(Err(format!("{e:?}")));
                }
            }
        });

        // Wait until either iOS prompts for PIN (`prompt_rx`) or an immediate error occurs (`result_rx`)
        let wait_outcome = engine.rt.block_on(async {
            tokio::select! {
                _ = prompt_rx => Ok(()),
                res = &mut result_rx => match res {
                    Ok(Ok(_)) => Ok(()),
                    Ok(Err(err_str)) => Err(err_str),
                    Err(_) => Err("pairing task terminated".to_string()),
                },
                _ = tokio::time::sleep(timeout) => Err("timed out waiting for device PIN prompt".to_string()),
            }
        });

        match wait_outcome {
            Ok(()) => {
                // Re-wrap result_rx into ActivePairing
                let (fwd_tx, fwd_rx) = tokio::sync::oneshot::channel::<Result<Vec<u8>, MyLocStatus>>();
                engine.rt.spawn(async move {
                    match result_rx.await {
                        Ok(Ok(bytes)) => { let _ = fwd_tx.send(Ok(bytes)); }
                        _ => { let _ = fwd_tx.send(Err(MyLocStatus::PairVerifyRejected)); }
                    }
                });
                if let Ok(mut guard) = engine.pairing.lock() {
                    *guard = Some(ActivePairing {
                        pin_tx: Some(pin_tx),
                        result_rx: fwd_rx,
                        task_handle,
                    });
                }
                engine.set_last_with_msg(MyLocStatus::Ok, String::new())
            }
            Err(err_msg) => {
                task_handle.abort();
                engine.set_last_with_msg(MyLocStatus::PairVerifyRejected, err_msg)
            }
        }
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

/// Submits the 6-digit PIN shown on the device and writes the resulting pairing file bytes into `out_buf`.
#[unsafe(no_mangle)]
pub extern "C" fn myloc_engine_submit_pairing_pin(
    handle: *mut MyLocEngineHandle,
    pin: *const c_char,
    out_buf: *mut u8,
    out_cap: usize,
    out_len: *mut usize,
) -> i32 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() || pin.is_null() || out_buf.is_null() || out_len.is_null() || out_cap == 0 {
            return MyLocStatus::InvalidArgument as i32;
        }
        let engine = unsafe { &*handle };
        let pin_str = match unsafe { CStr::from_ptr(pin) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return engine.set_last(MyLocStatus::InvalidArgument),
        };

        let mut active = match engine.pairing.lock() {
            Ok(mut guard) => match guard.take() {
                Some(p) => p,
                None => return engine.set_last(MyLocStatus::NotConnected),
            },
            Err(_) => return engine.set_last(MyLocStatus::InternalError),
        };

        if let Some(tx) = active.pin_tx.take() {
            let _ = tx.send(pin_str);
        }

        let outcome = engine.rt.block_on(async {
            match tokio::time::timeout(Duration::from_secs(15), active.result_rx).await {
                Ok(Ok(Ok(bytes))) => Ok(bytes),
                Ok(Ok(Err(e))) => Err(e),
                _ => Err(MyLocStatus::PairVerifyRejected),
            }
        });

        match outcome {
            Ok(bytes) => {
                if bytes.len() > out_cap {
                    return engine.set_last(MyLocStatus::InternalError);
                }
                unsafe {
                    std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf, bytes.len());
                    *out_len = bytes.len();
                }
                engine.set_last(MyLocStatus::Ok)
            }
            Err(status) => {
                active.task_handle.abort();
                engine.set_last(status)
            }
        }
    }));
    res.unwrap_or(MyLocStatus::InternalError as i32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn lifecycle_and_validation() {
        let handle = myloc_engine_create();
        assert!(!handle.is_null());

        // Invalid coordinates rejected
        assert_eq!(
            myloc_engine_set_location(handle, 95.0, 0.0),
            MyLocStatus::InvalidArgument as i32
        );
        assert_eq!(
            myloc_engine_set_location(handle, 0.0, 181.0),
            MyLocStatus::InvalidArgument as i32
        );
        assert_eq!(
            myloc_engine_set_location(handle, f64::NAN, 0.0),
            MyLocStatus::InvalidArgument as i32
        );

        // Valid coordinates when disconnected returns NotConnected
        assert_eq!(
            myloc_engine_set_location(handle, 39.9042, 116.4074),
            MyLocStatus::NotConnected as i32
        );
        assert_eq!(
            myloc_engine_clear_location(handle),
            MyLocStatus::NotConnected as i32
        );

        // Invalid pairing bytes returns PairingRecord
        let host = CString::new("127.0.0.1").unwrap();
        let bad_pairing = b"not a plist";
        assert_eq!(
            myloc_engine_connect(
                handle,
                host.as_ptr(),
                49152,
                bad_pairing.as_ptr(),
                bad_pairing.len(),
                1000
            ),
            MyLocStatus::PairingRecord as i32
        );

        assert_eq!(myloc_engine_disconnect(handle), MyLocStatus::Ok as i32);
        myloc_engine_destroy(handle);
    }

    #[test]
    fn probe_unreachable_port() {
        let host = CString::new("127.0.0.1").unwrap();
        // Port 1 is almost certainly closed
        let code = myloc_engine_probe_tunnel(host.as_ptr(), 1, 300);
        assert_eq!(code, MyLocStatus::TunnelUnreachable as i32);
    }
}
