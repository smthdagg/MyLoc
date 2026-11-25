use idevice::IdeviceService;
use idevice::provider::UsbmuxdProvider;
use idevice::remote_pairing::RemotePairingLockdownService;
use idevice::remote_pairing::RpPairingFile;
use idevice::usbmuxd::{UsbmuxdAddr, UsbmuxdConnection};
use std::env;
use std::fs;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let udid = args.get(1).expect("usage: export_pairing <UDID> <OUT_PATH>");
    let out_path = args.get(2).expect("usage: export_pairing <UDID> <OUT_PATH>");

    let mut conn = UsbmuxdConnection::default().await?;
    let dev = conn
        .get_device(udid)
        .await
        .map_err(|e| format!("get_device({udid}): {e:?}"))?;

    let provider = UsbmuxdProvider {
        addr: UsbmuxdAddr::default(),
        tag: 0,
        udid: dev.udid.clone(),
        device_id: dev.device_id,
        label: "MyLoc".to_string(),
    };

    let lockdown_rp = RemotePairingLockdownService::connect(&provider).await?;
    let mut client = lockdown_rp.into_client("MyLoc")?;
    let mut rp_file = RpPairingFile::generate("MyLoc");
    println!("Connecting RPPairing over USB — tap Trust on iPhone if prompted...");
    client
        .connect(&mut rp_file, || async { "000000".to_string() })
        .await?;

    let bytes = rp_file.to_bytes();
    fs::write(out_path, &bytes)?;
    println!("Exported RpPairingFile ({} bytes) to {}", bytes.len(), out_path);
    Ok(())
}
