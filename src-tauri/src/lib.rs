// Botvinnik desktop shell: the web app plus a native Stockfish sidecar,
// bridged to the webview as a line-oriented UCI pipe.

use std::sync::Mutex;
use tauri::{AppHandle, Emitter, State};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;

struct Engine(Mutex<Option<CommandChild>>);

#[tauri::command]
fn engine_start(app: AppHandle, state: State<'_, Engine>) -> Result<(), String> {
    let mut slot = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(old) = slot.take() {
        let _ = old.kill();
    }
    let (mut rx, child) = app
        .shell()
        .sidecar("stockfish")
        .map_err(|e| e.to_string())?
        .spawn()
        .map_err(|e| e.to_string())?;
    *slot = Some(child);

    let emitter = app.clone();
    tauri::async_runtime::spawn(async move {
        while let Some(event) = rx.recv().await {
            match event {
                CommandEvent::Stdout(bytes) => {
                    let _ =
                        emitter.emit("engine-line", String::from_utf8_lossy(&bytes).to_string());
                }
                CommandEvent::Error(e) => {
                    let _ = emitter.emit("engine-error", e);
                }
                CommandEvent::Terminated(_) => {
                    let _ = emitter.emit("engine-exit", ());
                }
                _ => {}
            }
        }
    });
    Ok(())
}

#[tauri::command]
fn engine_send(command: String, state: State<'_, Engine>) -> Result<(), String> {
    let mut slot = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(child) = slot.as_mut() {
        child
            .write(format!("{command}\n").as_bytes())
            .map_err(|e| e.to_string())?;
        Ok(())
    } else {
        Err("engine not running".into())
    }
}

#[tauri::command]
fn engine_stop(state: State<'_, Engine>) -> Result<(), String> {
    let mut slot = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(mut child) = slot.take() {
        let _ = child.write(b"quit\n");
        let _ = child.kill();
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(Engine(Mutex::new(None)))
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
