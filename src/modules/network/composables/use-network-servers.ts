// SPDX-License-Identifier: GPL-3.0-or-later
// License: GNU GPLv3 or later. See the license file in the project root for more information.
// Copyright © 2021 - present Aleksey Hoffman. All rights reserved.

import { computed } from 'vue';
import { invoke } from '@tauri-apps/api/core';
import { useUserSettingsStore } from '@/stores/storage/user-settings';
import type { NetworkServer } from '@/types/user-settings';

export const DEFAULT_REMOTE_MOUNT_DIR = '~/Remote';

export type NetworkServerDraft = Omit<NetworkServer, 'id'>;

export function getDefaultMountPath(mountName: string): string {
  return `${DEFAULT_REMOTE_MOUNT_DIR}/${mountName}`;
}

export function getServerMountPathLabel(server: NetworkServer): string {
  return server.mountPath.trim() || getDefaultMountPath(server.mountName);
}

export function getServerSourceLabel(server: NetworkServer): string {
  const userPrefix = server.username ? `${server.username}@` : '';
  const portSuffix = server.protocol === 'sshfs' && server.port ? `:${server.port}` : '';
  return `${userPrefix}${server.host}${portSuffix} ${server.remotePath}`;
}

function isSameServer(first: NetworkServerDraft, second: NetworkServerDraft): boolean {
  return first.protocol === second.protocol
    && first.host === second.host
    && (first.port ?? null) === (second.port ?? null)
    && first.username === second.username
    && first.remotePath === second.remotePath;
}

function createServerId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `server-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function useNetworkServers() {
  const userSettingsStore = useUserSettingsStore();

  const servers = computed<NetworkServer[]>(() => userSettingsStore.userSettings.networkServers ?? []);

  /** Adds the server, or updates the existing entry for the same host/user/path. */
  async function saveServer(draft: NetworkServerDraft): Promise<NetworkServer> {
    const current = servers.value;
    const existing = current.find(server => isSameServer(server, draft));
    const saved: NetworkServer = {
      ...draft,
      id: existing?.id ?? createServerId(),
    };

    const next = existing
      ? current.map(server => (server.id === existing.id ? saved : server))
      : [...current, saved];

    await userSettingsStore.set('networkServers', next);
    return saved;
  }

  async function removeServer(serverId: string): Promise<void> {
    await userSettingsStore.set(
      'networkServers',
      servers.value.filter(server => server.id !== serverId),
    );
  }

  /**
   * Mounts a saved server. Returns the real mount point.
   * Mounting an already mounted server is a no-op that returns the same path.
   * The password is never stored, so key-based SSH (or guest/anonymous) access is expected.
   */
  async function mountServer(server: NetworkServer, password?: string): Promise<string> {
    return invoke<string>('mount_network_share', {
      params: {
        protocol: server.protocol,
        host: server.host,
        port: server.port,
        username: server.username || null,
        password: password || null,
        remote_path: server.remotePath,
        mount_name: server.mountName,
        mount_path: server.mountPath.trim() || null,
      },
    });
  }

  return {
    servers,
    saveServer,
    removeServer,
    mountServer,
  };
}
