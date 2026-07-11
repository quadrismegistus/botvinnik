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
fn engine_start(app: AppHandle, state: State<'_, Engines>, id: String) -> Result<(), String> {
    let mut slots = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(mut old) = slots.remove(&id) {
        let _ = old.write(b"quit\n");
        let _ = old.kill();
    }
    let (mut rx, child) = app
        .shell()
        .sidecar("stockfish")
        .map_err(|e| e.to_string())?
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

#[tauri::command]
fn engine_send(state: State<'_, Engines>, id: String, command: String) -> Result<(), String> {
    let mut slots = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(child) = slots.get_mut(&id) {
        child
            .write(format!("{command}\n").as_bytes())
            .map_err(|e| e.to_string())?;
        Ok(())
    } else {
        Err(format!("engine {id} not running"))
    }
}

#[tauri::command]
fn engine_stop(state: State<'_, Engines>, id: String) -> Result<(), String> {
    let mut slots = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(mut child) = slots.remove(&id) {
        let _ = child.write(b"quit\n");
        let _ = child.kill();
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(Engines(Mutex::new(HashMap::new())))
        .invoke_handler(tauri::generate_handler![engine_start, engine_send, engine_stop])
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
