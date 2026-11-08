// SPDX-License-Identifier: GPL-3.0-or-later
// License: GNU GPLv3 or later. See the license file in the project root for more information.
// Copyright © 2021 - present Aleksey Hoffman. All rights reserved.

#[cfg(not(windows))]
use std::fs;

use super::types::NetworkShareParams;

pub fn mount_network_share(params: NetworkShareParams) -> Result<String, String> {
    #[cfg(windows)]
    {
        mount_network_share_windows(&params)
    }

    #[cfg(not(windows))]
    {
        let mount_point = resolve_mount_point(&params)?;

        // Clicking a saved server twice must not fail: an existing mount is a success.
        if is_mount_point_active(&mount_point) {
            return Ok(mount_point);
        }

        let existed_before = std::path::Path::new(&mount_point).exists();

        fs::create_dir_all(&mount_point)
            .map_err(|dir_error| format!("Failed to create mount point: {}", dir_error))?;

        let result = match params.protocol.as_str() {
            "sshfs" => mount_sshfs(&params, &mount_point),
            "nfs" => mount_nfs(&params, &mount_point),
            "smb" => mount_smb(&params, &mount_point),
            unknown => Err(format!("Unknown protocol: {}", unknown)),
        };

        if result.is_err() && !existed_before {
            // remove_dir only removes an empty directory, so this cannot delete user data.
            let _ = fs::remove_dir(&mount_point);
        }

        result.map(|_| mount_point)
    }
}

/// Picks the folder to mount into: the user's custom path, else the platform default.
#[cfg(not(windows))]
fn resolve_mount_point(params: &NetworkShareParams) -> Result<String, String> {
    let custom_path = params
        .mount_path
        .as_deref()
        .map(str::trim)
        .filter(|path| !path.is_empty());

    if let Some(custom_path) = custom_path {
        if custom_path.contains('\0') {
            return Err("Mount path contains an invalid character".to_string());
        }

        let expanded = if custom_path == "~" {
            home_dir_string()?
        } else if let Some(rest) = custom_path.strip_prefix("~/") {
            format!("{}/{}", home_dir_string()?, rest)
        } else {
            custom_path.to_string()
        };

        if !expanded.starts_with('/') {
            return Err("Mount path must be absolute (or start with ~/)".to_string());
        }

        return Ok(expanded.trim_end_matches('/').to_string());
    }

    let mount_name = params.mount_name.trim();
    if mount_name.is_empty()
        || mount_name == "."
        || mount_name == ".."
        || mount_name.contains('/')
        || mount_name.contains('\0')
    {
        return Err("Mount name must be a single folder name without '/'".to_string());
    }

    #[cfg(target_os = "macos")]
    {
        Ok(format!("/Volumes/{}", mount_name))
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(format!("{}/Remote/{}", home_dir_string()?, mount_name))
    }
}

#[cfg(not(windows))]
fn home_dir_string() -> Result<String, String> {
    dirs::home_dir()
        .map(|path| path.to_string_lossy().trim_end_matches('/').to_string())
        .ok_or_else(|| "Could not determine the home directory".to_string())
}

/// True when something is already mounted exactly at `mount_point`.
#[cfg(not(windows))]
fn is_mount_point_active(mount_point: &str) -> bool {
    #[cfg(target_os = "linux")]
    {
        // Mount points with spaces appear as `\040` in /proc/self/mounts.
        let escaped = mount_point.replace(' ', "\\040");
        std::fs::read_to_string("/proc/self/mounts")
            .map(|mounts| {
                mounts
                    .lines()
                    .any(|line| line.split_whitespace().nth(1) == Some(escaped.as_str()))
            })
            .unwrap_or(false)
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = mount_point;
        false
    }
}

#[cfg(windows)]
fn mount_network_share_windows(params: &NetworkShareParams) -> Result<String, String> {
    match params.protocol.as_str() {
        "smb" => {
            let unc_path = format!("\\\\{}\\{}", params.host, params.remote_path);

            let mut args = vec!["use", "*", &unc_path];

            let password_arg;
            if let Some(ref password) = params.password {
                password_arg = format!("/user:{}", params.username.as_deref().unwrap_or(""));
                args.push(&password_arg);
                args.push(password);
            }

            let output = std::process::Command::new("net")
                .args(&args)
                .output()
                .map_err(|run_error| format!("Failed to run 'net use': {}", run_error))?;

            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                let drive_letter = stdout
                    .lines()
                    .find(|line| line.contains("assigned"))
                    .and_then(|line| line.split_whitespace().last())
                    .unwrap_or("")
                    .to_string();
                Ok(drive_letter)
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                Err(format!("net use failed: {}", stderr.trim()))
            }
        }
        "sshfs" => {
            Err("SSHFS on Windows requires WinFSP and sshfs-win. Install from https://github.com/winfsp/sshfs-win".to_string())
        }
        "nfs" => {
            Err("NFS on Windows requires 'Services for NFS' Windows feature to be enabled".to_string())
        }
        unknown => Err(format!("Unknown protocol: {}", unknown)),
    }
}

#[cfg(not(windows))]
fn mount_sshfs(params: &NetworkShareParams, mount_point: &str) -> Result<(), String> {
    let username = params.username.as_deref().unwrap_or("root");
    let port = params.port.unwrap_or(22);
    let source = format!("{}@{}:{}", username, params.host, params.remote_path);

    let mut command = std::process::Command::new("sshfs");
    command.args([
        &source,
        mount_point,
        "-p",
        &port.to_string(),
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "ServerAliveInterval=15",
    ]);

    if params.password.is_some() {
        command.args(["-o", "password_stdin"]);
    }

    let output = if let Some(ref password) = params.password {
        use std::io::Write;
        let mut child = command
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|spawn_error| {
                format!("Failed to run sshfs: {}. Is sshfs installed?", spawn_error)
            })?;

        if let Some(ref mut stdin) = child.stdin {
            let _ = stdin.write_all(password.as_bytes());
        }

        child
            .wait_with_output()
            .map_err(|wait_error| format!("sshfs process error: {}", wait_error))?
    } else {
        command.output().map_err(|run_error| {
            format!("Failed to run sshfs: {}. Is sshfs installed?", run_error)
        })?
    };

    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        Err(format!("sshfs failed: {}", stderr.trim()))
    }
}

#[cfg(not(windows))]
fn mount_nfs(params: &NetworkShareParams, mount_point: &str) -> Result<(), String> {
    let source = format!("{}:{}", params.host, params.remote_path);

    let output = std::process::Command::new("mount")
        .args(["-t", "nfs4", &source, mount_point])
        .output()
        .or_else(|_| {
            std::process::Command::new("mount")
                .args(["-t", "nfs", &source, mount_point])
                .output()
        })
        .map_err(|run_error| format!("Failed to run mount: {}", run_error))?;

    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        Err(format!("NFS mount failed: {}", stderr.trim()))
    }
}

#[cfg(not(windows))]
fn mount_smb(params: &NetworkShareParams, mount_point: &str) -> Result<(), String> {
    let source = format!("//{}/{}", params.host, params.remote_path);

    #[cfg(target_os = "macos")]
    {
        let mount_source = if let Some(ref username) = params.username {
            format!("//{}@{}/{}", username, params.host, params.remote_path)
        } else {
            source.clone()
        };

        let output = std::process::Command::new("mount")
            .args(["-t", "smbfs", &mount_source, mount_point])
            .output()
            .map_err(|run_error| format!("Failed to run mount: {}", run_error))?;

        if output.status.success() {
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(format!("SMB mount failed: {}", stderr.trim()));
    }

    #[cfg(not(target_os = "macos"))]
    {
        let gio_uri = if let Some(ref username) = params.username {
            format!("smb://{}@{}/{}", username, params.host, params.remote_path)
        } else {
            format!("smb://{}/{}", params.host, params.remote_path)
        };

        if let Ok(output) = std::process::Command::new("gio")
            .args(["mount", &gio_uri])
            .output()
        {
            if output.status.success() {
                return Ok(());
            }
        }

        let mut mount_args = vec!["-t", "cifs", &source, mount_point];
        let options = if let Some(ref username) = params.username {
            if let Some(ref password) = params.password {
                format!("username={},password={}", username, password)
            } else {
                format!("username={}", username)
            }
        } else {
            "guest".to_string()
        };
        mount_args.extend(["-o", &options]);

        let output = std::process::Command::new("mount")
            .args(&mount_args)
            .output()
            .map_err(|run_error| format!("Failed to run mount: {}", run_error))?;

        if output.status.success() {
            Ok(())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            Err(format!("SMB mount failed: {}", stderr.trim()))
        }
    }
}

#[cfg(all(test, not(windows)))]
mod tests {
    use super::*;

    fn params(mount_name: &str, mount_path: Option<&str>) -> NetworkShareParams {
        NetworkShareParams {
            protocol: "sshfs".to_string(),
            host: "example.test".to_string(),
            port: None,
            username: None,
            password: None,
            remote_path: "/".to_string(),
            mount_name: mount_name.to_string(),
            mount_path: mount_path.map(str::to_string),
        }
    }

    #[test]
    fn custom_absolute_path_is_used_without_trailing_slash() {
        let resolved = resolve_mount_point(&params("srv", Some("/mnt/custom/"))).unwrap();
        assert_eq!(resolved, "/mnt/custom");
    }

    #[test]
    fn tilde_path_expands_to_home() {
        let home = home_dir_string().unwrap();
        let resolved = resolve_mount_point(&params("srv", Some("~/Servers/a"))).unwrap();
        assert_eq!(resolved, format!("{}/Servers/a", home));
    }

    #[test]
    fn relative_custom_path_is_rejected() {
        assert!(resolve_mount_point(&params("srv", Some("relative/dir"))).is_err());
    }

    #[test]
    fn blank_custom_path_falls_back_to_default() {
        let resolved = resolve_mount_point(&params("srv", Some("   "))).unwrap();
        assert!(resolved.ends_with("/srv"));
    }

    #[cfg(not(target_os = "macos"))]
    #[test]
    fn default_path_is_home_remote_name() {
        let home = home_dir_string().unwrap();
        let resolved = resolve_mount_point(&params("srv", None)).unwrap();
        assert_eq!(resolved, format!("{}/Remote/srv", home));
    }

    #[test]
    fn unsafe_mount_names_are_rejected_for_default_path() {
        for name in ["", ".", "..", "a/b", "../x"] {
            assert!(resolve_mount_point(&params(name, None)).is_err(), "{name}");
        }
    }
}
