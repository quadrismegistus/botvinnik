// Botvinnik desktop shell: the web app plus native Stockfish sidecars,
// bridged to the webview as line-oriented UCI pipes. Multiple engines can
// run at once (id "main" = live analysis; the archive importer runs its own
// pool) so background work never steals the live engine.

use std::collections::HashMap;
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, State};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;

struct Engines(Mutex<HashMap<String, CommandChild>>);

#[derive(Clone, serde::Serialize)]
struct EngineLine {
    id: String,
    line: String,
}

#[tauri::command]
fn engine_start(
    app: AppHandle,
    state: State<'_, Engines>,
    id: String,
    engine: Option<String>,
    args: Option<Vec<String>>,
) -> Result<(), String> {
    // only bundled sidecars may be spawned — never arbitrary paths from JS
    let engine = engine.unwrap_or_else(|| "stockfish".to_string());
    if engine != "stockfish" && engine != "lc0" {
        return Err(format!("unknown engine: {engine}"));
    }
    let mut slots = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(mut old) = slots.remove(&id) {
        let _ = old.write(b"quit\n");
        let _ = old.kill();
    }
    let (mut rx, child) = app
        .shell()
        .sidecar(&engine)
        .map_err(|e| e.to_string())?
        .args(args.unwrap_or_default())
        .spawn()
        .map_err(|e| e.to_string())?;
    slots.insert(id.clone(), child);

    let emitter = app.clone();
    tauri::async_runtime::spawn(async move {
        while let Some(event) = rx.recv().await {
            match event {
                CommandEvent::Stdout(bytes) => {
                    let _ = emitter.emit(
                        "engine-line",
                        EngineLine {
                            id: id.clone(),
                            line: String::from_utf8_lossy(&bytes).to_string(),
                        },
                    );
                }
                CommandEvent::Error(e) => {
                    let _ = emitter.emit("engine-error", EngineLine { id: id.clone(), line: e });
                }
                CommandEvent::Terminated(_) => {
                    let _ = emitter.emit(
                        "engine-exit",
                        EngineLine {
                            id: id.clone(),
                            line: String::new(),
                        },
                    );
                }
                _ => {}
            }
        }
    });
    Ok(())
}

fn send_impl(engines: &Engines, id: &str, command: &str) -> Result<(), String> {
    let mut slots = engines.0.lock().map_err(|e| e.to_string())?;
    if let Some(child) = slots.get_mut(id) {
        child
            .write(format!("{command}\n").as_bytes())
            .map_err(|e| e.to_string())?;
        Ok(())
    } else {
        Err(format!("engine {id} not running"))
    }
}

fn stop_impl(engines: &Engines, id: &str) -> Result<(), String> {
    let mut slots = engines.0.lock().map_err(|e| e.to_string())?;
    if let Some(mut child) = slots.remove(id) {
        let _ = child.write(b"quit\n");
        let _ = child.kill();
    }
    Ok(())
}

#[tauri::command]
fn engine_send(state: State<'_, Engines>, id: String, command: String) -> Result<(), String> {
    send_impl(&state, &id, &command)
}

// The dala nets (hrschubert/dala-training): human-imitation lc0 networks with
// real lichess ratings. Fetched on first use from the author's GitHub release
// into app-data — the app never redistributes the weights. Filenames are
// pinned to the exact release assets the calibration gym measured.
fn dala_asset(band: u32) -> Option<&'static str> {
    match band {
        700 => Some("dala-700-00235000.pb.gz"),
        900 => Some("dala-900-00285000.pb.gz"),
        1300 => Some("dala-1300-00300000.pb.gz"),
        _ => None,
    }
}

#[tauri::command]
async fn dala_ensure_weights(app: AppHandle, band: u32) -> Result<String, String> {
    use tauri::Manager;
    let asset = dala_asset(band).ok_or_else(|| format!("no dala net for band {band}"))?;
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("dala");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let dest = dir.join(asset);
    if dest.exists() {
        return Ok(dest.to_string_lossy().to_string());
    }

    let url =
        format!("https://github.com/hrschubert/dala-training/releases/download/Release-v0/{asset}");
    let _ = app.emit(
        "dala-download",
        EngineLine { id: band.to_string(), line: "start".to_string() },
    );
    let resp = reqwest::get(&url).await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("download failed: HTTP {}", resp.status()));
    }
    // stream to a temp file, rename on success (a torn download must not be
    // mistaken for a cached net on the next launch)
    let tmp = dir.join(format!("{asset}.part"));
    {
        use futures_util::StreamExt;
        let mut file = std::fs::File::create(&tmp).map_err(|e| e.to_string())?;
        let mut stream = resp.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|e| e.to_string())?;
            std::io::Write::write_all(&mut file, &chunk).map_err(|e| e.to_string())?;
        }
    }
    std::fs::rename(&tmp, &dest).map_err(|e| e.to_string())?;
    let _ = app.emit(
        "dala-download",
        EngineLine { id: band.to_string(), line: "done".to_string() },
    );
    Ok(dest.to_string_lossy().to_string())
}

#[tauri::command]
fn engine_stop(state: State<'_, Engines>, id: String) -> Result<(), String> {
    stop_impl(&state, &id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn send_to_missing_engine_errors() {
        let engines = Engines(Mutex::new(HashMap::new()));
        let err = send_impl(&engines, "main", "uci").unwrap_err();
        assert!(err.contains("main"), "error should name the engine id: {err}");
    }

    #[test]
    fn stop_of_missing_engine_is_ok() {
        let engines = Engines(Mutex::new(HashMap::new()));
        assert!(stop_impl(&engines, "import-3").is_ok());
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(Engines(Mutex::new(HashMap::new())))
        .invoke_handler(tauri::generate_handler![
            engine_start,
            engine_send,
            engine_stop,
            dala_ensure_weights
        ])
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
